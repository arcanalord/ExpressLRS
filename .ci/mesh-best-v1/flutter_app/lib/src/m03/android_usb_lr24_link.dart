import 'dart:async';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import 'byte_stream_link.dart';

final class UsbSerialDeviceInfo {
  const UsbSerialDeviceInfo({
    required this.deviceId,
    required this.vendorId,
    required this.productId,
    required this.productName,
    required this.manufacturerName,
    required this.serialNumber,
  });

  final int deviceId;
  final int? vendorId;
  final int? productId;
  final String? productName;
  final String? manufacturerName;
  final String? serialNumber;
}

abstract interface class UsbSerialPortHandle {
  bool get isOpen;
  Stream<Uint8List> get input;
  Future<void> write(Uint8List bytes);
  Future<void> close();
}

abstract interface class UsbSerialBackend {
  Future<List<UsbSerialDeviceInfo>> listDevices();
  Stream<int> get detachedDeviceIds;

  Future<UsbSerialPortHandle> open({
    required int deviceId,
    required int baudRate,
  });
}

final class PluginUsbSerialBackend implements UsbSerialBackend {
  const PluginUsbSerialBackend();

  @override
  Future<List<UsbSerialDeviceInfo>> listDevices() async {
    final devices = await UsbSerial.listDevices();
    return <UsbSerialDeviceInfo>[
      for (final device in devices)
        if (device.deviceId != null)
          UsbSerialDeviceInfo(
            deviceId: device.deviceId!,
            vendorId: device.vid,
            productId: device.pid,
            productName: device.productName,
            manufacturerName: device.manufacturerName,
            serialNumber: device.serial,
          ),
    ];
  }

  @override
  Stream<int> get detachedDeviceIds {
    final source = UsbSerial.usbEventStream;
    if (source == null) return const Stream<int>.empty();
    return source
        .where((event) => event.event == UsbEvent.ACTION_USB_DETACHED)
        .map((event) => event.device?.deviceId)
        .whereType<int>();
  }

  @override
  Future<UsbSerialPortHandle> open({
    required int deviceId,
    required int baudRate,
  }) async {
    final port = await UsbSerial.createFromDeviceId(deviceId);
    if (port == null) {
      throw StateError('USB serial driver unavailable for device $deviceId');
    }
    final opened = await port.open();
    if (!opened) {
      throw StateError('USB serial open failed for device $deviceId');
    }
    try {
      await port.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      await port.setFlowControl(UsbPort.FLOW_CONTROL_OFF);
      await port.setDTR(true);
      await port.setRTS(true);
      final input = port.inputStream;
      if (input == null) {
        throw StateError('USB serial input stream unavailable');
      }
      return _PluginUsbSerialPortHandle(port, input);
    } on Object {
      await port.close();
      rethrow;
    }
  }
}

final class _PluginUsbSerialPortHandle implements UsbSerialPortHandle {
  _PluginUsbSerialPortHandle(this._port, this.input);

  final UsbPort _port;

  @override
  final Stream<Uint8List> input;

  bool _isOpen = true;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> write(Uint8List bytes) async {
    if (!_isOpen) throw StateError('USB serial port is closed');
    await _port.write(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    await _port.close();
  }
}

/// Android USB-UART implementation of the transport-neutral LR24 byte stream.
///
/// The rest of M03 only knows [Lr24ByteStreamLink]. USB permission prompts,
/// chip-specific serial drivers and Android lifecycle stay behind this class.
final class AndroidUsbLr24ByteStreamLink implements Lr24ByteStreamLink {
  AndroidUsbLr24ByteStreamLink._({
    required this.deviceId,
    required UsbSerialBackend backend,
    required UsbSerialPortHandle port,
  })  : _backend = backend,
        _port = port {
    _inputSubscription = _port.input.listen(
      (bytes) {
        if (!_received.isClosed) {
          _received.add(Uint8List.fromList(bytes));
        }
      },
      onError: (_) => _markDisconnected(),
      onDone: _markDisconnected,
    );
    _detachSubscription = _backend.detachedDeviceIds.listen((detachedId) {
      if (detachedId == deviceId) _markDisconnected();
    });
  }

  final int deviceId;
  final UsbSerialBackend _backend;
  final UsbSerialPortHandle _port;
  final StreamController<Uint8List> _received =
      StreamController<Uint8List>.broadcast(sync: true);

  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<int>? _detachSubscription;
  bool _closed = false;
  bool _detached = false;

  static Future<List<UsbSerialDeviceInfo>> listDevices({
    UsbSerialBackend backend = const PluginUsbSerialBackend(),
  }) =>
      backend.listDevices();

  static Future<AndroidUsbLr24ByteStreamLink> connect({
    required int deviceId,
    int baudRate = 115200,
    UsbSerialBackend backend = const PluginUsbSerialBackend(),
  }) async {
    final port = await backend.open(deviceId: deviceId, baudRate: baudRate);
    return AndroidUsbLr24ByteStreamLink._(
      deviceId: deviceId,
      backend: backend,
      port: port,
    );
  }

  @override
  bool get isOpen => !_closed && !_detached && _port.isOpen;

  @override
  Stream<Uint8List> get received => _received.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    if (!isOpen) throw StateError('LR24 USB link is unavailable');
    await _port.write(Uint8List.fromList(bytes));
  }

  void _markDisconnected() {
    _detached = true;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _detachSubscription?.cancel();
    _detachSubscription = null;
    await _port.close();
    await _received.close();
  }
}
