final class CrsfFrameDetector {
  const CrsfFrameDetector._();

  static bool containsValidFrame(List<int> bytes) {
    for (var offset = 0; offset + 4 <= bytes.length; offset++) {
      final length = bytes[offset + 1];
      if (length < 2 || length > 62) continue;
      final total = length + 2;
      if (offset + total > bytes.length) continue;
      final crcIndex = offset + total - 1;
      final expected = bytes[crcIndex];
      final actual = crc8DvbS2(bytes, offset + 2, crcIndex);
      if (actual == expected) return true;
    }
    return false;
  }

  static int crc8DvbS2(List<int> data, int start, int end) {
    var crc = 0;
    for (var i = start; i < end; i++) {
      crc ^= data[i] & 0xff;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0xd5) : (crc << 1);
        crc &= 0xff;
      }
    }
    return crc;
  }
}
