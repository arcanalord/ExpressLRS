import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

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

/// Android implementation backed by usb-serial-for-android through
/// flutter_serial_communication. M03 itself never depends on this plugin.
final class PluginUsbSerialBackend implements UsbSerialBackend {
  PluginUsbSerialBackend({FlutterSerialCommunication? plugin})
      : _plugin = plugin ?? FlutterSerialCommunication();

  final FlutterSerialCommunication _plugin;
  int? _activeDeviceId;

  @override
  Future<List<UsbSerialDeviceInfo>> listDevices() async {
    final devices = await _plugin.getAvailableDevices();
    return <UsbSerialDeviceInfo>[
      for (final device in devices)
        if (device.deviceId != null)
          UsbSerialDeviceInfo(
            deviceId: device.deviceId!,
            vendorId: device.vendorId,
            productId: device.productId,
            productName:
                device.productName.trim().isEmpty ? null : device.productName,
            manufacturerName: device.manufacturerName.trim().isEmpty
                ? null
                : device.manufacturerName,
            serialNumber:
                device.serialNumber.trim().isEmpty ? null : device.serialNumber,
          ),
    ];
  }

  @override
  Stream<int> get detachedDeviceIds => _plugin
      .getDeviceConnectionListener()
      .receiveBroadcastStream()
      .where((event) => event == false)
      .map((_) => _activeDeviceId)
      .where((deviceId) => deviceId != null)
      .cast<int>();

  @override
  Future<UsbSerialPortHandle> open({
    required int deviceId,
    required int baudRate,
  }) async {
    final devices = await _plugin.getAvailableDevices();
    DeviceInfo? selected;
    for (final device in devices) {
      if (device.deviceId == deviceId) {
        selected = device;
        break;
      }
    }
    if (selected == null) {
      throw StateError('USB serial device $deviceId is no longer available');
    }

    final connected = await _plugin.connect(selected, baudRate);
    if (!connected) {
      throw StateError('USB serial connect failed for device $deviceId');
    }
    try {
      await _plugin.setParameters(baudRate, 8, 1, 0);
      await _plugin.setDTR(true);
      await _plugin.setRTS(true);
      _activeDeviceId = deviceId;

      final input = _plugin
          .getSerialMessageListener()
          .receiveBroadcastStream()
          .map(_coerceSerialBytes);
      return _PluginUsbSerialPortHandle(
        plugin: _plugin,
        input: input,
        onClosed: () {
          if (_activeDeviceId == deviceId) _activeDeviceId = null;
        },
      );
    } on Object {
      await _plugin.disconnect();
      rethrow;
    }
  }

  static Uint8List _coerceSerialBytes(dynamic event) {
    if (event is Uint8List) return Uint8List.fromList(event);
    if (event is List<int>) return Uint8List.fromList(event);
    if (event is List) {
      return Uint8List.fromList(
        event.map((value) => (value as num).toInt() & 0xff).toList(),
      );
    }
    throw FormatException(
      'Unexpected Android serial event type: ${event.runtimeType}',
    );
  }
}

final class _PluginUsbSerialPortHandle implements UsbSerialPortHandle {
  _PluginUsbSerialPortHandle({
    required FlutterSerialCommunication plugin,
    required this.input,
    required void Function() onClosed,
  })  : _plugin = plugin,
        _onClosed = onClosed;

  final FlutterSerialCommunication _plugin;
  final void Function() _onClosed;

  @override
  final Stream<Uint8List> input;

  bool _isOpen = true;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> write(Uint8List bytes) async {
    if (!_isOpen) throw StateError('USB serial port is closed');
    final sent = await _plugin.write(Uint8List.fromList(bytes));
    if (!sent) throw StateError('USB serial write failed');
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    try {
      await _plugin.disconnect();
    } finally {
      _onClosed();
    }
  }
}

/// Android USB-UART implementation of the transport-neutral LR24 byte stream.
///
/// The rest of M03 only knows [Lr24ByteStreamLink]. USB permissions,
/// serial-driver details and Android lifecycle stay behind this class.
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
    UsbSerialBackend? backend,
  }) =>
      (backend ?? PluginUsbSerialBackend()).listDevices();

  static Future<AndroidUsbLr24ByteStreamLink> connect({
    required int deviceId,
    int baudRate = 115200,
    UsbSerialBackend? backend,
  }) async {
    final selectedBackend = backend ?? PluginUsbSerialBackend();
    final port = await selectedBackend.open(
      deviceId: deviceId,
      baudRate: baudRate,
    );
    return AndroidUsbLr24ByteStreamLink._(
      deviceId: deviceId,
      backend: selectedBackend,
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
