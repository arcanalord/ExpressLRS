using FpvOsd.Core;

namespace FpvOsd.Platform.Abstractions;

public readonly record struct VideoFrame(int Width, int Height, long TimestampMs, ReadOnlyMemory<byte> Bgra32);
public readonly record struct PcmChunk(long TimestampHns, long DurationHns, ReadOnlyMemory<byte> Pcm16Mono48k);

public interface IVideoStream : IAsyncDisposable
{
    StreamKind Kind { get; }
    ConnectionState State { get; }
    event Action<VideoFrame>? FrameReady;
    Task StartAsync(CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public interface IIncomingAudio : IAsyncDisposable
{
    bool BackendAvailable { get; }
    bool Muted { get; }
    event Action<PcmChunk>? PcmReady;
    void SetMuted(bool muted);
}

public interface IRecorder : IAsyncDisposable
{
    bool IsRecording { get; }
    Task StartAsync(StreamKind stream, bool includeAudio, CancellationToken cancellationToken);
    Task WriteVideoAsync(VideoFrame frame, CancellationToken cancellationToken);
    Task WriteAudioAsync(PcmChunk chunk, CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public interface IAlarmOutput
{
    Task SignalCenterMotionAsync(CancellationToken cancellationToken);
}

public interface ICameraControl
{
    Task SetDayModeAsync(CancellationToken cancellationToken);
    Task SetNightModeAsync(CancellationToken cancellationToken);
    Task ToggleIrCutAsync(CancellationToken cancellationToken);
}
