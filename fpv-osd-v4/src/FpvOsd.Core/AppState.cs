using System;

namespace FpvOsd.Core;

public enum StreamKind { Visible, Thermal }
public enum ConnectionState { Disconnected, Connecting, Playing, Recovering, Error }

public sealed record MotionResult(bool Triggered, double Score, long TimestampMs);

public sealed record VideoTelemetry(
    int Width = 0,
    int Height = 0,
    double Fps = 0,
    int SignalPercent = 0,
    double PacketLossPercent = 0,
    long LastFrameAgeMs = 0,
    int ReconnectAttempt = 0,
    int ReconnectMax = 5,
    string Decoder = "Auto");

public sealed class AppState
{
    public StreamKind Primary { get; private set; } = StreamKind.Visible;
    public StreamKind PipStream { get; private set; } = StreamKind.Thermal;
    public bool PipEnabled { get; private set; }
    public bool Recording { get; private set; }
    public bool IncomingAudioMuted { get; private set; }
    public bool MotionEnabled { get; private set; } = true;
    public bool MotionAudioEnabled { get; private set; } = true;
    public bool SettingsOpen { get; private set; }
    public ConnectionState Connection { get; private set; } = ConnectionState.Connecting;
    public MotionResult Motion { get; private set; } = new(false, 0, 0);
    public VideoTelemetry Telemetry { get; private set; } = new();

    public event Action? Changed;
    public event Action? ReconnectRequested;

    public void SelectStream(StreamKind stream)
    {
        if (Primary == stream) return;
        Primary = stream;
        PipStream = stream == StreamKind.Visible ? StreamKind.Thermal : StreamKind.Visible;
        NotifyChanged();
    }

    public void TogglePip()
    {
        PipEnabled = !PipEnabled;
        NotifyChanged();
    }

    public void ToggleRecording()
    {
        Recording = !Recording;
        NotifyChanged();
    }

    public void SetIncomingAudioMuted(bool muted)
    {
        if (IncomingAudioMuted == muted) return;
        IncomingAudioMuted = muted;
        NotifyChanged();
    }

    public void SetMotionAudioEnabled(bool enabled)
    {
        if (MotionAudioEnabled == enabled) return;
        MotionAudioEnabled = enabled;
        NotifyChanged();
    }

    public void SetMotionEnabled(bool enabled)
    {
        if (MotionEnabled == enabled) return;
        MotionEnabled = enabled;
        if (!enabled) Motion = new(false, 0, Motion.TimestampMs);
        NotifyChanged();
    }

    public void SetMotion(MotionResult result)
    {
        Motion = MotionEnabled ? result : new(false, result.Score, result.TimestampMs);
        NotifyChanged();
    }

    public void SetConnectionState(ConnectionState state)
    {
        if (Connection == state) return;
        Connection = state;
        NotifyChanged();
    }

    public void SetVideoTelemetry(VideoTelemetry telemetry)
    {
        ArgumentNullException.ThrowIfNull(telemetry);
        Telemetry = telemetry;
        NotifyChanged();
    }

    public void SetSettingsOpen(bool open)
    {
        if (SettingsOpen == open) return;
        SettingsOpen = open;
        NotifyChanged();
    }

    public void ToggleSettings() => SetSettingsOpen(!SettingsOpen);

    public void RequestReconnect()
    {
        Connection = ConnectionState.Connecting;
        NotifyChanged();
        ReconnectRequested?.Invoke();
    }

    private void NotifyChanged() => Changed?.Invoke();
}
