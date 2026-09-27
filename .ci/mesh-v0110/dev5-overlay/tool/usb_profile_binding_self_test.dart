import 'dart:io';

import '../lib/core/usb_profile_binding.dart';
import '../lib/platform/usb_profile_binding_store.dart';

void expectThat(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('mesh-usb-binding-');
  try {
    final store = UsbProfileBindingStore(root);
    expectThat(await store.load() == null, 'fresh store must be empty');

    const binding = UsbProfileBinding(
      profileId: 'MICOAIR_LR24_F_STOCK',
      vendorId: 0x10c4,
      productId: 0xea60,
      driver: 'Cp21xxSerialDriver',
      deviceName: 'CP2102 USB to UART Bridge Controller',
    );

    await store.save(binding);
    final loaded = await store.load();
    expectThat(loaded != null, 'binding must reload');
    expectThat(loaded!.profileId == binding.profileId, 'profile roundtrip');
    expectThat(
      loaded.matches(
        vendorId: 0x10c4,
        productId: 0xea60,
        driver: 'cp21xxserialdriver',
        deviceName: 'CP2102 USB to UART Bridge Controller',
      ),
      'same device evidence must match',
    );
    expectThat(
      !loaded.matches(
        vendorId: 0x10c4,
        productId: 0xea60,
        driver: 'Cp21xxSerialDriver',
        deviceName: 'Different USB UART',
      ),
      'different device name must not auto-bind',
    );
    expectThat(
      !loaded.matches(
        vendorId: 0x0403,
        productId: 0x6001,
        driver: 'FtdiSerialDriver',
        deviceName: 'CP2102 USB to UART Bridge Controller',
      ),
      'different VID/PID must not auto-bind',
    );

    await store.clear();
    expectThat(await store.load() == null, 'clear must remove binding');

    final file = File('${root.path}/usb_profile_binding_v1.json');
    await file.writeAsString('{not-json');
    expectThat(await store.load() == null, 'corrupt binding must fail closed');

    print('USB_PROFILE_BINDING_PASS');
  } finally {
    await root.delete(recursive: true);
  }
}
