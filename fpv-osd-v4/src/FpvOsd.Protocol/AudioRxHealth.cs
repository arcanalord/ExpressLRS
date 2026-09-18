namespace FpvOsd.Protocol;

public enum AudioRxState
{
    Offline,
    Online,
    Stale,
    Error
}

public sealed class AudioRxHealth
{
    private long? _lastPacketMs;
    private bool _hasError;

    public long? LastPacketMs => _lastPacketMs;
    public string? LastError { get; private set; }

    public void ObservePacket(long nowMs)
    {
        _lastPacketMs = nowMs;
        _hasError = false;
        LastError = null;
    }

    public void ObserveError(string message)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(message);
        _hasError = true;
        LastError = message;
    }

    public AudioRxState Evaluate(long nowMs, long staleAfterMs = 1_500)
    {
        if (staleAfterMs <= 0) throw new ArgumentOutOfRangeException(nameof(staleAfterMs));
        if (_hasError) return AudioRxState.Error;
        if (_lastPacketMs is null) return AudioRxState.Offline;
        return nowMs - _lastPacketMs.Value > staleAfterMs ? AudioRxState.Stale : AudioRxState.Online;
    }

    public void Reset()
    {
        _lastPacketMs = null;
        _hasError = false;
        LastError = null;
    }
}
