namespace FpvOsd.Protocol;

public sealed class RtpAudioClock
{
    public const uint SampleRate = 48_000;
    public const ulong HnsPerSecond = 10_000_000;

    private const long MaxForwardSamples = SampleRate * 10L;
    private const ulong MaxClockSkewHns = HnsPerSecond * 2UL;

    private bool _initialized;
    private uint _ssrc;
    private uint _lastRtpTimestamp;
    private ulong _lastMappedHns;

    public void Reset()
    {
        _initialized = false;
        _ssrc = 0;
        _lastRtpTimestamp = 0;
        _lastMappedHns = 0;
    }

    public ulong MapToHns(uint ssrc, uint rtpTimestamp, ulong arrivalMs)
    {
        var arrivalHns = checked(arrivalMs * 10_000UL);
        if (!_initialized || _ssrc != ssrc)
        {
            _initialized = true;
            _ssrc = ssrc;
            _lastRtpTimestamp = rtpTimestamp;
            _lastMappedHns = arrivalHns;
            return _lastMappedHns;
        }

        var forward = unchecked(rtpTimestamp - _lastRtpTimestamp);
        var deltaSamples = forward <= 0x7fffffffU
            ? (long)forward
            : -(long)unchecked(_lastRtpTimestamp - rtpTimestamp);

        if (deltaSamples <= 0)
        {
            var restartBackwardsSamples = -(long)SampleRate * 2;
            if (deltaSamples < restartBackwardsSamples)
            {
                _lastRtpTimestamp = rtpTimestamp;
                _lastMappedHns = Math.Max(_lastMappedHns, arrivalHns);
            }
            return _lastMappedHns;
        }

        var candidate = arrivalHns;
        if (deltaSamples <= MaxForwardSamples)
        {
            var deltaHns = (ulong)deltaSamples * HnsPerSecond / SampleRate;
            candidate = _lastMappedHns > ulong.MaxValue - deltaHns
                ? ulong.MaxValue
                : _lastMappedHns + deltaHns;
        }

        var skew = candidate >= arrivalHns ? candidate - arrivalHns : arrivalHns - candidate;
        if (skew > MaxClockSkewHns) candidate = arrivalHns;
        if (candidate < _lastMappedHns) candidate = _lastMappedHns;

        _lastRtpTimestamp = rtpTimestamp;
        _lastMappedHns = candidate;
        return candidate;
    }
}
