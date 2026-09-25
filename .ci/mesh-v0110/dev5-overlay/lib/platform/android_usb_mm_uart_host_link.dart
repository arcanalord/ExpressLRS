import 'dart:async';
import 'dart:typed_data';

import 'android_usb_serial_bridge.dart';
import 'mm_uart_external_radio_session.dart';

/// Adapts the existing Android USB serial bridge to the common MM-UART host
/// contract. This deliberately does not create a second native USB stack.
final class AndroidUsbMmUartHostLink implements MmUartHostLink {
  AndroidUsbMmUartHostLink({
    required this.bridge,
    required this.deviceId,
    this.baudRate = 115200,
  });

  final AndroidUsbSerialBridge bridge;
  final int deviceId;
  final int baudRate;

  StreamSubscription<AndroidUsbSerialEvent>? _subscription;
  void Function(Uint8List bytes) _receiver = (_) {};
  void Function(String reason) _disconnectHandler = (_) {};
  bool _opened = false;

  @override
  Future<void> open() async {
    if (_opened) return;
    _subscription = bridge.events.listen(_onEvent);
    try {
      await bridge.connect(deviceId, baudRate: baudRate);
      _opened = true;
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  void _onEvent(AndroidUsbSerialEvent event) {
    if (event is AndroidUsbSerialBytes) {
      _receiver(event.bytes);
      return;
    }
    if (event is AndroidUsbSerialState) {
      final state = '${event.status['state'] ?? ''}'.trim().toLowerCase();
      if (state == 'disconnected' ||
          state == 'detached' ||
          state == 'offline' ||
          state == 'error') {
        _disconnectHandler(
          '${event.status['error'] ?? 'USB_SERIAL_$state'}',
        );
      }
    }
  }

  @override
  Future<void> write(Uint8List bytes) => bridge.write(bytes);

  @override
  Future<void> close() async {
    final sub = _subscription;
    _subscription = null;
    _opened = false;
    await sub?.cancel();
    try {
      await bridge.disconnect();
    } catch (_) {}
  }

  @override
  void setReceiver(void Function(Uint8List bytes) receiver) {
    _receiver = receiver;
  }

  @override
  void setDisconnectHandler(void Function(String reason) handler) {
    _disconnectHandler = handler;
  }

  @override
  Map<String, Object?> describe() => {
        'type': 'android_usb_serial',
        'deviceId': deviceId,
        'baudRate': baudRate,
      };
}
