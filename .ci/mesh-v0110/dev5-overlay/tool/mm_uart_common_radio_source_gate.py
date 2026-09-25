from pathlib import Path

root = Path(__file__).resolve().parents[1]
codec = (root/'lib/platform/mm_uart_codec.dart').read_text()
session = (root/'lib/platform/mm_uart_external_radio_session.dart').read_text()
transport = (root/'lib/platform/mm_uart_message_transport.dart').read_text()
caps = (root/'lib/platform/radio_capability_contract.dart').read_text()

required_codec = [
    'mmUartCrc16Ccitt', 'mmUartCobsEncode', 'mmUartCobsDecode',
    'MmUartFrameType', 'txAccepted = 0x83', 'response = 0x90',
    'compatSelftest = 0x06',
]
required_session = [
    "'host': 'mesh-messenger-flutter'", 'MmUartFrameType.getInfo',
    'MmUartFrameType.getCaps', 'MmUartFrameType.getState',
    'supportsMmrp', "'messageId': messageId", "'payloadType': payloadType",
    'ExternalRadioTxAcceptedEvent', 'ExternalRadioPacketEvent',
]
required_transport = [
    "String get id => 'external-radio'", "case 'text':", "case 'map_point':",
    'TransportSendStatus.accepted', 'MmUartRecipientAck',
    "'transport_ack'", 'M02 keeps the envelope in waitingAck',
]
required_caps = [
    "networkProtocols.contains('MMRP/1')", 'rangingAvailable',
    "raw['rangingAvailable'] == true", 'waypointAvailable',
]

for needle in required_codec:
    assert needle in codec, needle
for needle in required_session:
    assert needle in session, needle
for needle in required_transport:
    assert needle in transport, needle
for needle in required_caps:
    assert needle in caps, needle

# Hard architectural gates.
assert 'SEND_TEXT' not in transport
assert 'R1|' not in transport
assert 'state == \'ready\' && session.supportsMmrp' in transport
assert 'DeliveryState.delivered' not in transport
assert 'recipientResult(' not in transport
assert "recipientBinding: '$binding'" in transport
print('MM_UART_COMMON_RADIO_SOURCE_GATE_PASS')
