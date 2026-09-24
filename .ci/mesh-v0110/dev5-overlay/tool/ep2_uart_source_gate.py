from pathlib import Path

root = Path(__file__).resolve().parents[1]
transport = (root / 'lib/platform/ep2_uart_transport.dart').read_text()
controller = (root / 'lib/src/application/mesh_app_controller.dart').read_text()
connection = (root / 'lib/src/features/connection/connection_page.dart').read_text()
models = (root / 'lib/core/models.dart').read_text()
delivery = (root / 'lib/core/delivery.dart').read_text()

checks = {
    'EP2 transport id': "String get id => 'ep2-uart'",
    'UART baud': 'ep2Baud = 115200',
    'current EP2 text command': 'SEND_TEXT',
    'incoming EP2 text': "case 'RX_TEXT'",
    'RF ACK': "case 'ACK'",
    'firmware READY': "case 'READY'",
    'firmware INFO': "case 'INFO'",
    'base64url payload': 'base64Url',
    'contact binding': 'ep2NodeId',
    'wifi ota command': 'startWifiUpdate',
    'ota ready event': 'Ep2OtaReadyEvent',
    'raw uart event': 'Ep2RawBytesEvent',
}
for label, needle in checks.items():
    assert needle in transport or needle in controller or needle in models, f'missing {label}'

assert 'Радиомодуль · USB' in connection
assert 'Диагностика радиомодуля' in connection
assert 'EP2 / SX1280 · USB-UART' not in connection
assert 'EP2 LINK v0.2.0' not in connection
assert 'ep2NodeId' in models
assert 'for (final transport in candidates)' in delivery, 'delivery must support transport fallback'

# The Flutter transport intentionally speaks the currently built EP2 LINK v0.2
# line protocol. Do not reintroduce the older COBS/MM-UART session stack here.
assert 'cobs' not in transport.lower()
assert 'mm-uart' not in transport.lower()

print('EP2_UART_SOURCE_GATE_PASS')

assert 'Wi-Fi обновление' in connection
assert 'UART диагностика' in connection
assert 'ep2DetectedProtocol' in controller
