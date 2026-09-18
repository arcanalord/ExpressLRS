using System.Runtime.InteropServices;

namespace FpvOsd.Platform.Windows;

public readonly record struct H264DecoderProbeResult(
    bool RuntimeStarted,
    int SoftwareDecoderCount,
    int HardwareDecoderCount,
    string Detail)
{
    public bool DecoderAvailable => SoftwareDecoderCount > 0 || HardwareDecoderCount > 0;
}

public static class MediaFoundationH264DecoderProbe
{
    private const uint MfVersion = 0x00020070;
    private const uint MfStartupFull = 0;
    private const uint MftEnumFlagSyncMft = 0x00000001;
    private const uint MftEnumFlagHardware = 0x00000004;
    private const uint MftEnumFlagSortAndFilter = 0x00000040;

    private static readonly Guid MftCategoryVideoDecoder = new("D6C02D4B-6833-45B4-971A-05A4B04BAB91");
    private static readonly Guid MfMediaTypeVideo = new("73646976-0000-0010-8000-00AA00389B71");
    private static readonly Guid MfVideoFormatH264 = new("34363248-0000-0010-8000-00AA00389B71");
    private static readonly Guid MfVideoFormatNv12 = new("3231564E-0000-0010-8000-00AA00389B71");

    public static H264DecoderProbeResult Probe()
    {
        if (!OperatingSystem.IsWindows())
            return new(false, 0, 0, "Media Foundation H.264 decoder probe is Windows-only.");

        var started = false;
        try
        {
            var hr = MFStartup(MfVersion, MfStartupFull);
            if (hr < 0)
                return new(false, 0, 0, $"MFStartup failed: 0x{unchecked((uint)hr):X8}");
            started = true;

            var input = new MftRegisterTypeInfo(MfMediaTypeVideo, MfVideoFormatH264);
            var output = new MftRegisterTypeInfo(MfMediaTypeVideo, MfVideoFormatNv12);
            var software = CountDecoders(MftEnumFlagSyncMft | MftEnumFlagSortAndFilter, input, output);
            var hardware = CountDecoders(MftEnumFlagHardware | MftEnumFlagSortAndFilter, input, output);
            var detail = $"H.264->NV12 Media Foundation decoders: software={software}, hardware={hardware}.";
            return new(true, software, hardware, detail);
        }
        catch (DllNotFoundException ex)
        {
            return new(false, 0, 0, $"Media Foundation DLL not found: {ex.Message}");
        }
        catch (EntryPointNotFoundException ex)
        {
            return new(false, 0, 0, $"Media Foundation API not found: {ex.Message}");
        }
        finally
        {
            if (started) _ = MFShutdown();
        }
    }

    private static int CountDecoders(uint flags, MftRegisterTypeInfo input, MftRegisterTypeInfo output)
    {
        var hr = MFTEnumEx(in MftCategoryVideoDecoder, flags, in input, in output, out var activates, out var count);
        if (hr < 0) return 0;

        try
        {
            for (var i = 0; i < count; i++)
            {
                var activate = Marshal.ReadIntPtr(activates, checked((int)(i * (uint)IntPtr.Size)));
                if (activate != IntPtr.Zero) _ = Marshal.Release(activate);
            }
            return checked((int)count);
        }
        finally
        {
            if (activates != IntPtr.Zero) Marshal.FreeCoTaskMem(activates);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MftRegisterTypeInfo
    {
        public readonly Guid MajorType;
        public readonly Guid SubType;

        public MftRegisterTypeInfo(Guid majorType, Guid subType)
        {
            MajorType = majorType;
            SubType = subType;
        }
    }

    [DllImport("mfplat.dll", ExactSpelling = true)]
    private static extern int MFStartup(uint version, uint flags);

    [DllImport("mfplat.dll", ExactSpelling = true)]
    private static extern int MFShutdown();

    [DllImport("mfplat.dll", ExactSpelling = true)]
    private static extern int MFTEnumEx(
        in Guid guidCategory,
        uint flags,
        in MftRegisterTypeInfo inputType,
        in MftRegisterTypeInfo outputType,
        out IntPtr activates,
        out uint count);
}
