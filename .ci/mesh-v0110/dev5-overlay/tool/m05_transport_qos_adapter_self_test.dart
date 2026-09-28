import 'dart:async';
import 'dart:io';

import '../lib/platform/m05_transport_qos_adapter.dart';

Future<void> main() async {
  final written = <String>[];
  final gate = Completer<void>();
  var writes = 0;
  final adapter = M05TransportQosAdapter(
    maxFileBurst: 2,
    fileStarvationGuard: 4,
    writeRaw: (frame) async {
      writes++;
      if (writes == 1) await gate.future;
      written.add(frame['id'].toString());
    },
  );

  final firstFile = adapter.send(<String, Object?>{
    'p': 'FILE/1',
    'k': 'chunk',
    'id': 'f0',
  });
  await Future<void>.delayed(Duration.zero);

  final fileFutures = <Future<void>>[];
  for (var i = 1; i <= 6; i++) {
    fileFutures.add(
      adapter.send(<String, Object?>{
        'p': 'FILE/1',
        'k': 'chunk',
        'id': 'f$i',
      }),
    );
  }
  final text = adapter.send(<String, Object?>{
    'p': 'MMRP/1',
    'k': 'data',
    'class': 'text',
    'id': 'text-1',
  });
  final control = adapter.send(<String, Object?>{
    'p': 'MMRP/1',
    'k': 'ack',
    'id': 'ack-1',
  });

  gate.complete();
  await Future.wait(<Future<void>>[
    firstFile,
    ...fileFutures,
    text,
    control,
  ]);

  if (written.first != 'f0') {
    throw StateError('in-flight frame ordering changed: $written');
  }
  if (written[1] != 'ack-1' || written[2] != 'text-1') {
    throw StateError(
      'control/text did not preempt queued FILE/1: $written',
    );
  }

  if (adapter
          .classify(<String, Object?>{
            'p': 'MMRP/1',
            'k': 'channel_data',
            'class': 'text',
          })
          .name !=
      'text') {
    throw StateError('MMRP text classification failed');
  }
  if (adapter
          .classify(<String, Object?>{'p': 'FILE/1', 'k': 'chunk'})
          .name !=
      'file') {
    throw StateError('FILE/1 classification failed');
  }
  if (adapter
          .classify(<String, Object?>{'p': 'MMRP/1', 'k': 'ping'})
          .name !=
      'control') {
    throw StateError('control classification failed');
  }

  final saturationWritten = <String>[];
  final saturation = M05TransportQosAdapter(
    maxFileBurst: 2,
    fileStarvationGuard: 4,
    writeRaw: (frame) async {
      saturationWritten.add(frame['id'].toString());
    },
  );
  final futures = <Future<void>>[];
  for (var i = 0; i < 30; i++) {
    futures.add(
      saturation.send(<String, Object?>{
        'p': 'FILE/1',
        'k': 'chunk',
        'id': 'sf$i',
      }),
    );
    if (i % 3 == 0) {
      futures.add(
        saturation.send(<String, Object?>{
          'p': 'MMRP/1',
          'k': 'data',
          'class': 'text',
          'id': 'st$i',
        }),
      );
    }
    if (i % 7 == 0) {
      futures.add(
        saturation.send(<String, Object?>{
          'p': 'MMRP/1',
          'k': 'ack',
          'id': 'sc$i',
        }),
      );
    }
  }
  await Future.wait(futures);
  if (saturationWritten.length != futures.length) {
    throw StateError('saturation frame loss detected');
  }
  if (!saturation.isIdle) {
    throw StateError('adapter did not drain');
  }

  stdout.writeln('MESH_MESSENGER_M05_TRANSPORT_QOS_ADAPTER_PASS');
}
