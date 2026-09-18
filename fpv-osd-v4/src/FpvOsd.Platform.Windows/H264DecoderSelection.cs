namespace FpvOsd.Platform.Windows;

public enum H264DecoderKind
{
    Hardware,
    Software
}

public readonly record struct H264DecoderCandidate(H264DecoderKind Kind, int Index);

public readonly record struct H264DecoderSelectionResult(
    bool Opened,
    H264DecoderCandidate? Selected,
    int Attempts,
    string Detail);

public static class H264DecoderSelection
{
    public static IEnumerable<H264DecoderCandidate> AutoOrder(int hardwareCount, int softwareCount)
    {
        if (hardwareCount < 0) throw new ArgumentOutOfRangeException(nameof(hardwareCount));
        if (softwareCount < 0) throw new ArgumentOutOfRangeException(nameof(softwareCount));

        for (var i = 0; i < hardwareCount; i++)
            yield return new(H264DecoderKind.Hardware, i);

        for (var i = 0; i < softwareCount; i++)
            yield return new(H264DecoderKind.Software, i);
    }

    public static H264DecoderSelectionResult TryOpenAuto(
        int hardwareCount,
        int softwareCount,
        Func<H264DecoderCandidate, bool> tryOpen)
    {
        ArgumentNullException.ThrowIfNull(tryOpen);
        var attempts = 0;

        foreach (var candidate in AutoOrder(hardwareCount, softwareCount))
        {
            attempts++;
            try
            {
                if (tryOpen(candidate))
                {
                    return new(
                        true,
                        candidate,
                        attempts,
                        $"Opened {candidate.Kind} H.264 decoder #{candidate.Index} after {attempts} attempt(s).");
                }
            }
            catch
            {
                // One broken or incompatible MFT must never block fallback.
            }
        }

        return new(
            false,
            null,
            attempts,
            attempts == 0
                ? "No Media Foundation H.264 decoders were enumerated."
                : $"No compatible Media Foundation H.264 decoder opened after {attempts} attempt(s).");
    }
}
