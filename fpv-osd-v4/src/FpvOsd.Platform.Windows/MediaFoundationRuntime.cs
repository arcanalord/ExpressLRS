using System.Runtime.InteropServices;

namespace FpvOsd.Platform.Windows;

public static class MediaFoundationRuntime
{
    private const uint MfVersion = 0x00020070;
    private const uint MfStartupFull = 0;

    public static bool IsPlatformSupported => OperatingSystem.IsWindows();

    public static bool TryProbe(out string detail)
    {
        if (!OperatingSystem.IsWindows())
        {
            detail = "Media Foundation is available only on Windows.";
            return false;
        }

        var started = false;
        try
        {
            var hr = MFStartup(MfVersion, MfStartupFull);
            if (hr < 0)
            {
                detail = $"MFStartup failed: 0x{unchecked((uint)hr):X8}";
                return false;
            }

            started = true;
            detail = "Media Foundation runtime startup OK.";
            return true;
        }
        catch (DllNotFoundException ex)
        {
            detail = $"mfplat.dll not found: {ex.Message}";
            return false;
        }
        catch (EntryPointNotFoundException ex)
        {
            detail = $"Media Foundation entry point not found: {ex.Message}";
            return false;
        }
        finally
        {
            if (started) _ = MFShutdown();
        }
    }

    [DllImport("mfplat.dll", ExactSpelling = true)]
    private static extern int MFStartup(uint version, uint flags);

    [DllImport("mfplat.dll", ExactSpelling = true)]
    private static extern int MFShutdown();
}
