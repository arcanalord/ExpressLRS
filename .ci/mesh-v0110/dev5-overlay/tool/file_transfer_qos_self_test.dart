import 'dart:io';

import 'file_transfer_qos.dart';

void main() {
  final q = M05QosScheduler<String>(maxFileBurst: 3, fileStarvationGuard: 5);
  for (var i = 0; i < 20; i++) q.enqueue(M05TrafficClass.file, 'f$i');
  q.enqueue(M05TrafficClass.text, 't0');
  q.enqueue(M05TrafficClass.control, 'c0');
  final first = q.drain(budget: 5);
  if (first[0].value != 'c0' || first[1].value != 't0') {
    throw StateError(
      'control/text priority failed: ${first.map((e) => e.value).toList()}',
    );
  }

  final s = M05QosScheduler<String>(maxFileBurst: 2, fileStarvationGuard: 4);
  s.enqueue(M05TrafficClass.file, 'file');
  for (var i = 0; i < 10; i++) s.enqueue(M05TrafficClass.text, 't$i');
  final seen = <String>[];
  for (var i = 0; i < 5; i++) seen.add(s.takeNext()!.value);
  if (!seen.contains('file'))
    throw StateError('file starvation guard failed: $seen');

  final p = M05QosScheduler<String>(maxFileBurst: 2, fileStarvationGuard: 10);
  p.enqueue(M05TrafficClass.file, 'f0');
  p.enqueue(M05TrafficClass.file, 'f1');
  p.enqueue(M05TrafficClass.file, 'f2');
  p.enqueue(M05TrafficClass.control, 'c1');
  final order = p.drain(budget: 4).map((e) => e.value).toList();
  if (order.first != 'c1')
    throw StateError('late control was not preemptive: $order');

  final b = M05QosScheduler<int>();
  for (var i = 0; i < 100; i++) b.enqueue(M05TrafficClass.file, i);
  final batch = b.drain(budget: 7);
  if (batch.length != 7 || b.pendingFile != 93)
    throw StateError('budget bound failed');

  stdout.writeln('MESH_MESSENGER_M05_QOS_PASS');
}
