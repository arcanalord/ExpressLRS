namespace FpvOsd.Protocol;

public enum RtpMediaKind
{
    Unknown,
    H264Video,
    OpusAudio
}

public readonly record struct RtpPayloadMap(byte H264PayloadType, byte OpusPayloadType = 97)
{
    public RtpMediaKind Classify(in RtpPacket packet)
    {
        if (packet.PayloadType == OpusPayloadType) return RtpMediaKind.OpusAudio;
        if (packet.PayloadType == H264PayloadType) return RtpMediaKind.H264Video;
        return RtpMediaKind.Unknown;
    }
}
