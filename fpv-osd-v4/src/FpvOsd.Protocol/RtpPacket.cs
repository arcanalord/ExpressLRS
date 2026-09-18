namespace FpvOsd.Protocol;

public readonly record struct RtpPacket(
    byte PayloadType,
    bool Marker,
    ushort Sequence,
    uint Timestamp,
    uint Ssrc,
    ReadOnlyMemory<byte> Payload);

public static class RtpParser
{
    public static bool TryParse(ReadOnlyMemory<byte> datagram, out RtpPacket packet)
    {
        packet = default;
        var span = datagram.Span;
        if (span.Length < 12 || (span[0] >> 6) != 2) return false;

        var csrcCount = span[0] & 0x0f;
        var hasExtension = (span[0] & 0x10) != 0;
        var hasPadding = (span[0] & 0x20) != 0;
        var offset = 12 + csrcCount * 4;
        if (offset > span.Length) return false;

        if (hasExtension)
        {
            if (offset + 4 > span.Length) return false;
            var words = (span[offset + 2] << 8) | span[offset + 3];
            offset += 4 + words * 4;
            if (offset > span.Length) return false;
        }

        var payloadLength = span.Length - offset;
        if (hasPadding)
        {
            if (payloadLength == 0) return false;
            var padding = span[^1];
            if (padding == 0 || padding > payloadLength) return false;
            payloadLength -= padding;
        }

        packet = new RtpPacket(
            (byte)(span[1] & 0x7f),
            (span[1] & 0x80) != 0,
            ReadU16(span, 2),
            ReadU32(span, 4),
            ReadU32(span, 8),
            datagram.Slice(offset, payloadLength));
        return true;
    }

    private static ushort ReadU16(ReadOnlySpan<byte> s, int i) => (ushort)((s[i] << 8) | s[i + 1]);
    private static uint ReadU32(ReadOnlySpan<byte> s, int i) =>
        ((uint)s[i] << 24) | ((uint)s[i + 1] << 16) | ((uint)s[i + 2] << 8) | s[i + 3];
}
