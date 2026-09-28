import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../lib/core/file_transfer_core.dart';
import '../lib/platform/file1_transport_bridge.dart';
import '../lib/platform/m05_transport_qos_adapter.dart';
import '../lib/platform/mm_serial_codec.dart';

Future<void> main() async {
  await _runLoopback(bytes: 20 * 1024, chunkSize: 512);
  await _runLoopback(bytes: 100 * 1024, chunkSize: 1024);
  stdout.writeln('MESH_MESSENGER_FILE1_TRANSPORT_LOOPBACK_PASS');
}

Future<void> _runLoopback({
  required int bytes,
  required int chunkSize,
}) async {
  final codecA = MmSerialCodec();
  final codecB = MmSerialCodec();
  late final File1TransportBridge bridgeA;
  late final File1TransportBridge bridgeB;
  Uint8List? received;

  Future<void> deliver(
    MmSerialCodec encoder,
    MmSerialCodec decoder,
    File1TransportBridge target,
    Uint8List payload,
  ) async {
    final wire = encoder.encodeBinary(
      payload,
      tag: MmSerialCodec.file1BinaryTag,
    );
    for (var offset = 0; offset < wire.length; offset += 37) {
      final end = (offset + 37 < wire.length) ? offset + 37 : wire.length;
      final packets = decoder.feedPackets(
        Uint8List.fromList(wire.sublist(offset, end)),
      );
      for (final packet in packets) {
        if (packet is! MmSerialBinaryPacket ||
            packet.tag != MmSerialCodec.file1BinaryTag) {
          throw StateError('unexpected MM-SERIAL packet');
        }
        await target.handleIncoming(packet.payload);
      }
    }
  }

  late final M05TransportQosAdapter qosA;
  late final M05TransportQosAdapter qosB;
  qosA = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: (payload) => deliver(codecA, codecB, bridgeB, payload),
  );
  qosB = M05TransportQosAdapter(
    writeRaw: (_) async {},
    writeRawFile1: (payload) => deliver(codecB, codecA, bridgeA, payload),
  );
  bridgeA = File1TransportBridge(
    sendBytes: qosA.sendFile1,
    onReceived: (_) {},
  );
  bridgeB = File1TransportBridge(
    sendBytes: qosB.sendFile1,
    onReceived: (event) {
      received = Uint8List.fromList(event.bytes);
    },
  );

  final payload = Uint8List.fromList(
    List<int>.generate(bytes, (index) => (index * 43 + bytes) & 0xff),
  );
  final plan = M05FileTransferCore.createPlan(
    transferId: 'loopback-$bytes',
    fileName: 'loopback-$bytes.bin',
    mimeType: 'application/octet-stream',
    bytes: payload,
    chunkSize: chunkSize,
  );

  await bridgeA.send(plan).timeout(const Duration(seconds: 10));
  final result = received;
  if (result == null || !_same(payload, result)) {
    throw StateError('FILE/1 loopback payload mismatch for $bytes bytes');
  }
  if (codecA.badFrames != 0 || codecB.badFrames != 0) {
    throw StateError('MM-SERIAL bad frames in FILE/1 loopback');
  }
  bridgeA.close();
  bridgeB.close();
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
