using System.Net;
using System.Net.Sockets;
using FpvOsd.Core;
using FpvOsd.Platform.Windows;
using FpvOsd.Protocol;
using FpvOsd.Transport;

var passed = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException("FAIL: " + name);
    passed++;
    Console.WriteLine("PASS: " + name);
}

static RtpPacket Packet(byte pt, bool marker, ushort seq, uint ts, uint ssrc, params byte[] payload) =>
    new(pt, marker, seq, ts, ssrc, payload);

var state = new AppState();
Check(state.Primary == StreamKind.Visible, "default stream visible");
state.SelectStream(StreamKind.Thermal);
Check(state.Primary == StreamKind.Thermal && state.PipStream == StreamKind.Visible, "stream switch swaps PiP peer");
state.ToggleRecording();
Check(state.Recording, "recording toggle");
Check(state.Connection == ConnectionState.Connecting, "operator state starts connecting");
var stateChanges = 0;
state.Changed += () => stateChanges++;
state.SetConnectionState(ConnectionState.Recovering);
Check(state.Connection == ConnectionState.Recovering && stateChanges == 1, "connection state notifies UI");
state.SetVideoTelemetry(new VideoTelemetry(1920, 1080, 59.9, 94, 0.2, 1800, 2, 5, "Hardware #0"));
Check(state.Telemetry.Width == 1920 && state.Telemetry.ReconnectAttempt == 2, "video telemetry stored");
state.SetSettingsOpen(true);
Check(state.SettingsOpen, "settings drawer state");
state.SetMotion(new MotionResult(true, 0.86, 1234));
Check(state.Motion.Triggered, "motion alert state");
var reconnectRaised = false;
state.ReconnectRequested += () => reconnectRaised = true;
state.RequestReconnect();
Check(reconnectRaised && state.Connection == ConnectionState.Connecting, "reconnect request returns to connecting");


var rtp = new byte[]
{
    0x80, 0x61, 0x12, 0x34,
    0x00, 0x00, 0x03, 0xC0,
    0x11, 0x22, 0x33, 0x44,
    0xF8, 0xFF, 0xFE
};
Check(RtpParser.TryParse(rtp, out var packet), "RTP parse");
Check(packet.PayloadType == 97, "Opus PT97");
Check(packet.Sequence == 0x1234, "RTP sequence");
Check(packet.Timestamp == 960, "RTP timestamp");
Check(packet.Ssrc == 0x11223344, "RTP SSRC");
Check(packet.Payload.Length == 3, "RTP payload size");
Check(!RtpParser.TryParse(new byte[] { 0x80, 0x61 }, out _), "RTP rejects short datagram");

var clock = new RtpAudioClock();
var t0 = clock.MapToHns(1, 1000, 5000);
var t1 = clock.MapToHns(1, 1960, 5020);
Check(t1 >= t0, "audio clock monotonic");
Check(t1 - t0 == 200_000, "48 kHz 20 ms RTP delta");

var wrap = new RtpAudioClock();
var w0 = wrap.MapToHns(7, 0xffff_ff00, 1000);
var w1 = wrap.MapToHns(7, 0x0000_02c0, 1020);
Check(w1 >= w0, "RTP wrap monotonic");

var ssrcClock = new RtpAudioClock();
var s0 = ssrcClock.MapToHns(1, 1000, 1000);
var s1 = ssrcClock.MapToHns(2, 100, 1050);
Check(s1 >= s0 && s1 == 10_500_000, "audio clock SSRC rebase");

var jumpClock = new RtpAudioClock();
_ = jumpClock.MapToHns(1, 1000, 1000);
var jump = jumpClock.MapToHns(1, 1_000_000, 1100);
Check(jump == 11_000_000, "audio clock large jump rebases to arrival");

var reorderClock = new RtpAudioClock();
var ro0 = reorderClock.MapToHns(1, 5000, 1000);
var ro1 = reorderClock.MapToHns(1, 4900, 1001);
Check(ro1 == ro0, "audio clock reorder clamps monotonic");

var restartClock = new RtpAudioClock();
var rs0 = restartClock.MapToHns(1, 200_000, 1000);
var rs1 = restartClock.MapToHns(1, 1_000, 1100);
Check(rs1 >= rs0, "audio clock backwards restart rebase");

var map = new RtpPayloadMap(96);
Check(map.Classify(Packet(96, false, 1, 1, 1, 0x65)) == RtpMediaKind.H264Video, "RTP media classifies H264");
Check(map.Classify(Packet(97, false, 1, 1, 1, 0xF8)) == RtpMediaKind.OpusAudio, "RTP media classifies Opus PT97");
Check(map.Classify(Packet(98, false, 1, 1, 1, 0x00)) == RtpMediaKind.Unknown, "RTP media rejects unknown PT");

var health = new AudioRxHealth();
Check(health.Evaluate(1000) == AudioRxState.Offline, "audio RX starts offline");
health.ObservePacket(1000);
Check(health.Evaluate(1200) == AudioRxState.Online, "audio RX becomes online");
Check(health.Evaluate(2600) == AudioRxState.Stale, "audio RX becomes stale");
health.ObserveError("decoder failure");
Check(health.Evaluate(2600) == AudioRxState.Error && health.LastError is not null, "audio RX exposes error");
health.ObservePacket(2700);
Check(health.Evaluate(2700) == AudioRxState.Online && health.LastError is null, "audio RX packet clears error");

var single = new H264RtpDepacketizer();
Check(single.TryPush(Packet(96, true, 1, 90_000, 5, 0x65, 0xAA, 0xBB), out var singleAu), "H264 single NAL emits access unit");
Check(singleAu.IsKeyFrame, "H264 single IDR marks keyframe");
Check(singleAu.Timestamp == 90_000 && singleAu.Ssrc == 5, "H264 access unit preserves RTP context");
Check(singleAu.AnnexB.Span.SequenceEqual(new byte[] { 0, 0, 0, 1, 0x65, 0xAA, 0xBB }), "H264 single NAL converted to Annex B");

var fua = new H264RtpDepacketizer();
Check(!fua.TryPush(Packet(96, false, 10, 1234, 7, 0x7C, 0x85, 0xAA, 0xBB), out _), "H264 FU-A start waits for end");
Check(fua.TryPush(Packet(96, true, 11, 1234, 7, 0x7C, 0x45, 0xCC, 0xDD), out var fuAu), "H264 FU-A end emits access unit");
Check(fuAu.IsKeyFrame, "H264 FU-A reconstructs IDR type");
Check(fuAu.AnnexB.Span.SequenceEqual(new byte[] { 0, 0, 0, 1, 0x65, 0xAA, 0xBB, 0xCC, 0xDD }), "H264 FU-A reconstructs Annex B NAL");

var stap = new H264RtpDepacketizer();
var stapPayload = new byte[] { 0x78, 0, 2, 0x67, 0x11, 0, 2, 0x68, 0x22 };
Check(stap.TryPush(Packet(96, true, 20, 2222, 8, stapPayload), out var stapAu), "H264 STAP-A emits access unit");
Check(stapAu.AnnexB.Span.SequenceEqual(new byte[] { 0, 0, 0, 1, 0x67, 0x11, 0, 0, 0, 1, 0x68, 0x22 }), "H264 STAP-A expands NAL units");

var gap = new H264RtpDepacketizer();
Check(!gap.TryPush(Packet(96, false, 30, 3000, 9, 0x7C, 0x85, 0x01), out _), "H264 gap test FU-A start accepted");
Check(!gap.TryPush(Packet(96, true, 32, 3000, 9, 0x7C, 0x45, 0x02), out _), "H264 packet gap drops incomplete FU-A");
Check(gap.TryPush(Packet(96, true, 33, 4000, 9, 0x61, 0x10), out _), "H264 recovers after packet gap");

var malformedStap = new H264RtpDepacketizer();
Check(!malformedStap.TryPush(Packet(96, true, 40, 5000, 10, 0x78, 0, 10, 0x67), out _), "H264 rejects malformed STAP-A");
var unsupportedNal = new H264RtpDepacketizer();
Check(!unsupportedNal.TryPush(Packet(96, true, 41, 5001, 10, 0x7D, 0x00), out _), "H264 rejects unsupported RTP packetization type");

await using (var receiver = new UdpRtpReceiver(0, IPAddress.Loopback))
{
    var received = new TaskCompletionSource<RtpPacket>(TaskCreationOptions.RunContinuationsAsynchronously);
    var malformed = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
    receiver.PacketReceived += p => received.TrySetResult(p);
    receiver.MalformedDatagram += length => malformed.TrySetResult(length);
    await receiver.StartAsync();
    Check(receiver.IsRunning && receiver.LocalPort > 0, "UDP RTP receiver starts on ephemeral port");

    using var sender = new UdpClient();
    await sender.SendAsync(rtp, rtp.Length, new IPEndPoint(IPAddress.Loopback, receiver.LocalPort));
    var loopPacket = await received.Task.WaitAsync(TimeSpan.FromSeconds(2));
    Check(loopPacket.PayloadType == 97 && loopPacket.Sequence == 0x1234, "UDP loopback receives and parses RTP");

    var bad = new byte[] { 1, 2, 3 };
    await sender.SendAsync(bad, bad.Length, new IPEndPoint(IPAddress.Loopback, receiver.LocalPort));
    Check(await malformed.Task.WaitAsync(TimeSpan.FromSeconds(2)) == 3, "UDP loopback reports malformed datagram");

    await receiver.StopAsync();
    Check(!receiver.IsRunning && receiver.LocalPort == 0, "UDP RTP receiver stops cleanly");
}

var videoClock = new RtpVideoClock();
var v0 = videoClock.Map(90_000, 1, 1000);
var v1 = videoClock.Map(93_000, 1, 1033);
Check(v1 > v0 && v1 - v0 == 333_333, "90 kHz video clock maps 3000 ticks to ~33.333 ms");

var videoWrap = new RtpVideoClock();
var vw0 = videoWrap.Map(0xffff_ff00, 7, 1000);
var vw1 = videoWrap.Map(0x0000_02c0, 7, 1011);
Check(vw1 >= vw0, "video RTP wrap stays monotonic");

var videoSsrc = new RtpVideoClock();
var vs0 = videoSsrc.Map(90_000, 1, 1000);
var vs1 = videoSsrc.Map(1_000, 2, 1050);
Check(vs1 >= vs0 && vs1 == 10_500_000, "video clock SSRC change rebases to arrival");

var blackNv12 = new byte[] { 16, 16, 16, 16, 128, 128 };
var blackBgra = Nv12Converter.ToBgra32(blackNv12, 2, 2);
Check(blackBgra.Length == 16, "NV12 2x2 converts to four BGRA pixels");
Check(blackBgra[0] == 0 && blackBgra[1] == 0 && blackBgra[2] == 0 && blackBgra[3] == 255,
    "NV12 limited-range black converts to opaque black");

var whiteNv12 = new byte[] { 235, 235, 235, 235, 128, 128 };
var whiteBgra = Nv12Converter.ToBgra32(whiteNv12, 2, 2);
Check(whiteBgra[0] >= 250 && whiteBgra[1] >= 250 && whiteBgra[2] >= 250 && whiteBgra[3] == 255,
    "NV12 limited-range white converts to opaque white");

var nv12Rejected = false;
try { _ = Nv12Converter.ToBgra32(new byte[4], 2, 2); }
catch (ArgumentException) { nv12Rejected = true; }
Check(nv12Rejected, "NV12 converter rejects undersized buffers");

if (OperatingSystem.IsWindows())
{
    Check(MediaFoundationRuntime.TryProbe(out var mfDetail), "Windows Media Foundation runtime probe: " + mfDetail);
    var decoderProbe = MediaFoundationH264DecoderProbe.Probe();
    Check(decoderProbe.RuntimeStarted, "Windows H264 decoder probe runtime starts");
    Check(decoderProbe.DecoderAvailable, decoderProbe.Detail);
}
else
{
    Check(!MediaFoundationRuntime.TryProbe(out _), "Media Foundation probe is Windows-gated");
    var decoderProbe = MediaFoundationH264DecoderProbe.Probe();
    Check(!decoderProbe.RuntimeStarted && !decoderProbe.DecoderAvailable, "H264 decoder probe is Windows-gated");
}

Console.WriteLine($"ALL V4-M1 SMOKE TESTS PASSED: {passed}");
