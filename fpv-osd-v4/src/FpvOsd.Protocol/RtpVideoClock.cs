using System;

namespace FpvOsd.Protocol;

public sealed class RtpVideoClock
{
    private const long HnsPerSecond = 10_000_000;
    private const long RtpTicksPerSecond = 90_000;
    private const int RestartThresholdTicks = 5 * 90_000;

    private bool _hasState;
    private uint _ssrc;
    private uint _lastTimestamp;
    private long _lastHns;

    public long Map(uint timestamp, uint ssrc, long arrivalMs)
    {
        var arrivalHns = checked(arrivalMs * 10_000L);

        if (!_hasState)
        {
            _hasState = true;
            _ssrc = ssrc;
            _lastTimestamp = timestamp;
            _lastHns = arrivalHns;
            return _lastHns;
        }

        if (ssrc != _ssrc)
            return Rebase(timestamp, ssrc, arrivalHns);

        var deltaTicks = unchecked((int)(timestamp - _lastTimestamp));
        if (deltaTicks > RestartThresholdTicks || deltaTicks < -RestartThresholdTicks)
            return Rebase(timestamp, ssrc, arrivalHns);

        if (deltaTicks <= 0)
            return _lastHns;

        var deltaHns = checked((long)deltaTicks * HnsPerSecond / RtpTicksPerSecond);
        _lastTimestamp = timestamp;
        _lastHns = checked(_lastHns + deltaHns);
        return _lastHns;
    }

    public void Reset()
    {
        _hasState = false;
        _ssrc = 0;
        _lastTimestamp = 0;
        _lastHns = 0;
    }

    private long Rebase(uint timestamp, uint ssrc, long arrivalHns)
    {
        _ssrc = ssrc;
        _lastTimestamp = timestamp;
        _lastHns = Math.Max(_lastHns, arrivalHns);
        return _lastHns;
    }
}
