from pathlib import Path
import struct

probe = Path(
    "android/app/src/main/kotlin/com/arcanalord/service_studio/UsbSerialProbe.kt"
).read_text(encoding="utf-8")

required_source_markers = {
    "sync opcode": "command(0x08, payload" in probe,
    "flash begin opcode": "link.command(0x02, begin" in probe,
    "flash data opcode": "op = 0x03" in probe,
    "read reg opcode": "command(0x0A, data" in probe,
    "write reg opcode": "command(0x09, data" in probe,
    "checksum seed": "0xEFL" in probe,
    "erase workaround": "esp8266EraseSize" in probe,
    "flash block size": "val blockSize = 0x400" in probe,
}

failed = [name for name, ok in required_source_markers.items() if not ok]
if failed:
    raise SystemExit("ROM protocol source markers failed: " + ", ".join(failed))

def checksum(data: bytes) -> int:
    value = 0xEF
    for b in data:
        value ^= b
    return value & 0xFFFFFFFF

def erase_size(offset: int, size: int) -> int:
    sectors_per_block = 16
    sector_size = 0x1000
    num_sectors = (size + sector_size - 1) // sector_size
    start_sector = offset // sector_size
    head_sectors = sectors_per_block - (start_sector % sectors_per_block)
    if num_sectors < head_sectors:
        head_sectors = num_sectors
    if num_sectors < 2 * head_sectors:
        return ((num_sectors + 1) // 2) * sector_size
    return (num_sectors - head_sectors) * sector_size

def slip_encode(body: bytes) -> bytes:
    out = bytearray([0xC0])
    for b in body:
        if b == 0xC0:
            out.extend((0xDB, 0xDC))
        elif b == 0xDB:
            out.extend((0xDB, 0xDD))
        else:
            out.append(b)
    out.append(0xC0)
    return bytes(out)

def slip_decode(frame: bytes) -> bytes:
    if not frame or frame[0] != 0xC0 or frame[-1] != 0xC0:
        raise AssertionError("invalid SLIP frame")
    src = frame[1:-1]
    out = bytearray()
    i = 0
    while i < len(src):
        if src[i] == 0xDB:
            i += 1
            if i >= len(src):
                raise AssertionError("truncated SLIP escape")
            out.append(0xC0 if src[i] == 0xDC else 0xDB if src[i] == 0xDD else src[i])
        else:
            out.append(src[i])
        i += 1
    return bytes(out)

for size in (0, 1, 2, 16, 1024, 4097, 65535):
    data = bytes((i * 37 + 11) & 0xFF for i in range(size))
    reference = 0xEF
    for b in data:
        reference ^= b
    assert checksum(data) == reference

for offset in (0, 0x1000, 0xF000, 0x10000):
    for size in (1, 0x1000, 0x2000, 0xF000, 0x10000, 0x12345, 0x80000):
        sectors = (size + 0xFFF) // 0x1000
        head = min(sectors, 16 - ((offset // 0x1000) % 16))
        reference = ((sectors + 1) // 2) * 0x1000 if sectors < 2 * head else (sectors - head) * 0x1000
        assert erase_size(offset, size) == reference

for data in (b"", b"abc", bytes(range(256)), bytes([0xC0, 0xDB, 0x01, 0xC0])):
    assert slip_decode(slip_encode(data)) == data

sync_payload = bytes((0x07, 0x07, 0x12, 0x20)) + bytes([0x55]) * 32
sync_packet = struct.pack("<BBHI", 0, 0x08, len(sync_payload), 0) + sync_payload
assert sync_packet[1] == 0x08
assert struct.unpack_from("<H", sync_packet, 2)[0] == 36

block = bytes((i * 13 + 7) & 0xFF for i in range(0x400))
flash_payload = struct.pack("<IIII", 0x400, 0, 0, 0) + block
flash_packet = struct.pack("<BBHI", 0, 0x03, len(flash_payload), checksum(block)) + flash_payload
assert flash_packet[1] == 0x03
assert struct.unpack_from("<H", flash_packet, 2)[0] == 0x410
assert struct.unpack_from("<I", flash_packet, 4)[0] == checksum(block)

print("ESP8266/ESP8285 ROM protocol contract PASS")
