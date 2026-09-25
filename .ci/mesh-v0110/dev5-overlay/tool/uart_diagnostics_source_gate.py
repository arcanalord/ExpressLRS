#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
transport = (root / 'lib/platform/ep2_uart_transport.dart').read_text(encoding='utf-8')
probe = (root / 'lib/platform/radio_uart_probe.dart').read_text(encoding='utf-8')
controller = (root / 'lib/src/application/mesh_app_controller.dart').read_text(encoding='utf-8')
page = (root / 'lib/src/features/connection/connection_page.dart').read_text(encoding='utf-8')

required_transport = [
    'connectAuto',
    'ep2Baud = 115200',
    'crsfBaud = 420000',
    'CMD,$sequence,PING,$targetNode',
    "case 'LINK':",
    "case 'RADIO_STATS':",
    'CrsfFrameDetector.containsValidFrame',
]
for needle in required_transport:
    assert needle in transport, needle

for needle in ['crc8DvbS2', 'length < 2 || length > 62']:
    assert needle in probe, needle

for needle in ['pingEp2Neighbor', "ep2Protocol = switch", 'ep2Rssi10']:
    assert needle in controller, needle

for needle in ['PING соседнего узла', "'Повторить'", "'Авто'", 'ELRS / CRSF']:
    assert needle in page, needle

# Keep engineering details out of the normal device list.
assert 'VID:' not in page and 'PID:' not in page
print('UART diagnostics source gate: PASS')
