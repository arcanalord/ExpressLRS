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

for needle in ['pingEp2Neighbor', "ep2Protocol = switch", 'ep2Rssi10', 'connectLr24', 'TransparentUartRadioTransport']:
    assert needle in controller, needle

for needle in [
    'PING соседнего узла',
    "'Авто M03'",
    'LR24-F выбран',
    'UART диагностика M03 / ELRS',
    'ELRS / CRSF',
]:
    assert needle in page, needle

# LR24 and M03 are mutually exclusive modes; the old generic retry action
# must not be shown beside an already selected LR24 transport.
assert "'Повторить'" not in page

# Keep engineering details out of the normal device list.
assert 'VID:' not in page and 'PID:' not in page
print('UART diagnostics source gate: PASS')
