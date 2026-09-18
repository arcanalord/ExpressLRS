using FpvOsd.Platform.Windows;

static void Check(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException("FAIL: " + name);
    Console.WriteLine("PASS: " + name);
}

var order = H264DecoderSelection.AutoOrder(2, 2).ToArray();
Check(order.Length == 4, "all decoder candidates are enumerated");
Check(order[0].Kind == H264DecoderKind.Hardware && order[1].Kind == H264DecoderKind.Hardware,
    "hardware decoders are tried first");
Check(order[2].Kind == H264DecoderKind.Software && order[3].Kind == H264DecoderKind.Software,
    "software decoders follow hardware decoders");

var secondHardware = H264DecoderSelection.TryOpenAuto(
    2,
    1,
    candidate => candidate.Kind == H264DecoderKind.Hardware && candidate.Index == 1);
Check(secondHardware.Opened && secondHardware.Selected?.Kind == H264DecoderKind.Hardware && secondHardware.Attempts == 2,
    "failure of first hardware decoder falls through to next hardware decoder");

var softwareFallback = H264DecoderSelection.TryOpenAuto(
    2,
    2,
    candidate => candidate.Kind == H264DecoderKind.Software && candidate.Index == 0);
Check(softwareFallback.Opened && softwareFallback.Selected?.Kind == H264DecoderKind.Software && softwareFallback.Attempts == 3,
    "hardware failures fall back to software decoder");

var exceptionFallback = H264DecoderSelection.TryOpenAuto(
    1,
    1,
    candidate => candidate.Kind == H264DecoderKind.Software
        ? true
        : throw new InvalidOperationException("simulated broken hardware MFT"));
Check(exceptionFallback.Opened && exceptionFallback.Selected?.Kind == H264DecoderKind.Software && exceptionFallback.Attempts == 2,
    "exception from one MFT does not stop fallback");

var unavailable = H264DecoderSelection.TryOpenAuto(1, 1, _ => false);
Check(!unavailable.Opened && unavailable.Attempts == 2,
    "decoder unavailable only after all candidates fail");

Console.WriteLine("ALL WINDOWS H264 DECODER POLICY TESTS PASSED");
