import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/m03/android_usb_lr24_link.dart';

void main() {
  test('Android USB LR24 link copies RX/TX bytes and reacts to detach', () async {
    final backend = _FakeUsbBackend();
    final link = await AndroidUsbLr24ByteStreamLink.connect(
      deviceId: 42,
      baudRate: 115200,
      backend: backend,
    );

    expect(link.isOpen, isTrue);
    expect(backend.openedDeviceId, 42);
    expect(backend.openedBaudRate, 115200);

    final received = <Uint8List>[];
    final sub = link.received.listen(received.add);

    final rx = Uint8List.fromList(<int>[1, 2, 3]);
    backend.port.emit(rx);
    rx[0] = 99;
    await Future<void>.delayed(Duration.zero);
    expect(received.single, <int>[1, 2, 3]);

    final tx = Uint8List.fromList(<int>[7, 8, 9]);
    await link.write(tx);
    tx[0] = 55;
    expect(backend.port.writes.single, <int>[7, 8, 9]);

    backend.detach.add(41);
    await Future<void>.delayed(Duration.zero);
    expect(link.isOpen, isTrue);

    backend.detach.add(42);
    await Future<void>.delayed(Duration.zero);
    expect(link.isOpen, isFalse);

    expect(
      () => link.write(Uint8List.fromList(<int>[1])),
      throwsA(isA<StateError>()),
    );

    await sub.cancel();
    await link.close();
    expect(backend.port.closeCount, 1);
  });

  test('device listing stays behind backend boundary', () async {
    final backend = _FakeUsbBackend();
    backend.devices = const <UsbSerialDeviceInfo>[
      UsbSerialDeviceInfo(
        deviceId: 7,
        vendorId: 0x10c4,
        productId: 0xea60,
        productName: 'CP210x',
        manufacturerName: 'Silicon Labs',
        serialNumber: 'abc',
      ),
    ];

    final devices =
        await AndroidUsbLr24ByteStreamLink.listDevices(backend: backend);
    expect(devices, hasLength(1));
    expect(devices.single.deviceId, 7);
    expect(devices.single.vendorId, 0x10c4);
    expect(devices.single.productId, 0xea60);
  });
}

final class _FakeUsbBackend implements UsbSerialBackend {
  final _FakeUsbPort port = _FakeUsbPort();
  final StreamController<int> detach =
      StreamController<int>.broadcast(sync: true);
  List<UsbSerialDeviceInfo> devices = const <UsbSerialDeviceInfo>[];
  int? openedDeviceId;
  int? openedBaudRate;

  @override
  Future<List<UsbSerialDeviceInfo>> listDevices() async =>
      List<UsbSerialDeviceInfo>.unmodifiable(devices);

  @override
  Stream<int> get detachedDeviceIds => detach.stream;

  @override
  Future<UsbSerialPortHandle> open({
    required int deviceId,
    required int baudRate,
  }) async {
    openedDeviceId = deviceId;
    openedBaudRate = baudRate;
    port.open = true;
    return port;
  }
}

final class _FakeUsbPort implements UsbSerialPortHandle {
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>.broadcast(sync: true);
  final List<Uint8List> writes = <Uint8List>[];
  bool open = false;
  int closeCount = 0;

  @override
  bool get isOpen => open;

  @override
  Stream<Uint8List> get input => controller.stream;

  void emit(Uint8List bytes) => controller.add(bytes);

  @override
  Future<void> write(Uint8List bytes) async {
    if (!open) throw StateError('fake port closed');
    writes.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close() async {
    if (!open) return;
    open = false;
    closeCount++;
  }
}
