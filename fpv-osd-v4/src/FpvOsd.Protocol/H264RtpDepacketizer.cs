namespace FpvOsd.Protocol;

public readonly record struct H264AccessUnit(
    ReadOnlyMemory<byte> AnnexB,
    uint Timestamp,
    uint Ssrc,
    bool IsKeyFrame);

public sealed class H264RtpDepacketizer
{
    private static readonly byte[] StartCode = [0, 0, 0, 1];
    private readonly int _maxAccessUnitBytes;
    private readonly List<byte> _buffer = [];
    private bool _fuActive;
    private uint _timestamp;
    private uint _ssrc;
    private bool _hasContext;
    private bool _keyFrame;
    private bool _hasLastSequence;
    private ushort _lastSequence;

    public H264RtpDepacketizer(int maxAccessUnitBytes = 4 * 1024 * 1024)
    {
        if (maxAccessUnitBytes < 1024) throw new ArgumentOutOfRangeException(nameof(maxAccessUnitBytes));
        _maxAccessUnitBytes = maxAccessUnitBytes;
    }

    public bool TryPush(in RtpPacket packet, out H264AccessUnit accessUnit)
    {
        accessUnit = default;
        var payload = packet.Payload.Span;
        if (payload.IsEmpty) return false;

        var sequenceContinuous = !_hasLastSequence || (ushort)(_lastSequence + 1) == packet.Sequence;
        _lastSequence = packet.Sequence;
        _hasLastSequence = true;
        if (!sequenceContinuous) ResetAssembly();

        if (_hasContext && (packet.Timestamp != _timestamp || packet.Ssrc != _ssrc)) ResetAssembly();
        if (!_hasContext)
        {
            _timestamp = packet.Timestamp;
            _ssrc = packet.Ssrc;
            _hasContext = true;
        }

        var nalType = payload[0] & 0x1f;
        var accepted = nalType switch
        {
            >= 1 and <= 23 => PushSingleNal(payload),
            24 => PushStapA(payload),
            28 => PushFuA(payload),
            _ => false
        };

        if (!accepted)
        {
            ResetAssembly();
            return false;
        }

        if (_buffer.Count > _maxAccessUnitBytes)
        {
            ResetAssembly();
            return false;
        }

        if (!packet.Marker) return false;
        if (_fuActive || _buffer.Count == 0)
        {
            ResetAssembly();
            return false;
        }

        accessUnit = new H264AccessUnit(_buffer.ToArray(), _timestamp, _ssrc, _keyFrame);
        ResetAssembly();
        return true;
    }

    public void Reset()
    {
        ResetAssembly();
        _hasLastSequence = false;
        _lastSequence = 0;
    }

    private bool PushSingleNal(ReadOnlySpan<byte> payload)
    {
        if (_fuActive) return false;
        AppendStartCode();
        Append(payload);
        if ((payload[0] & 0x1f) == 5) _keyFrame = true;
        return true;
    }

    private bool PushStapA(ReadOnlySpan<byte> payload)
    {
        if (_fuActive || payload.Length < 3) return false;
        var offset = 1;
        while (offset < payload.Length)
        {
            if (offset + 2 > payload.Length) return false;
            var length = (payload[offset] << 8) | payload[offset + 1];
            offset += 2;
            if (length <= 0 || offset + length > payload.Length) return false;
            var nal = payload.Slice(offset, length);
            AppendStartCode();
            Append(nal);
            if ((nal[0] & 0x1f) == 5) _keyFrame = true;
            offset += length;
        }
        return offset == payload.Length;
    }

    private bool PushFuA(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 3) return false;
        var fuHeader = payload[1];
        var start = (fuHeader & 0x80) != 0;
        var end = (fuHeader & 0x40) != 0;
        var reserved = (fuHeader & 0x20) != 0;
        var nalType = fuHeader & 0x1f;
        if (reserved || nalType == 0 || (start && end)) return false;

        if (start)
        {
            if (_fuActive) return false;
            _fuActive = true;
            AppendStartCode();
            var reconstructedHeader = (byte)((payload[0] & 0xe0) | nalType);
            _buffer.Add(reconstructedHeader);
            if (nalType == 5) _keyFrame = true;
        }
        else if (!_fuActive)
        {
            return false;
        }

        Append(payload[2..]);
        if (end) _fuActive = false;
        return true;
    }

    private void AppendStartCode() => _buffer.AddRange(StartCode);

    private void Append(ReadOnlySpan<byte> data)
    {
        for (var i = 0; i < data.Length; i++) _buffer.Add(data[i]);
    }

    private void ResetAssembly()
    {
        _buffer.Clear();
        _fuActive = false;
        _hasContext = false;
        _timestamp = 0;
        _ssrc = 0;
        _keyFrame = false;
    }
}
