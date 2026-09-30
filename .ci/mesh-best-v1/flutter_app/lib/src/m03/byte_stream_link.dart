import 'dart:async';
import 'dart:typed_data';

abstract interface class Lr24ByteStreamLink {
  bool get isOpen;
  Stream<Uint8List> get received;
  Future<void> write(Uint8List bytes);
}

final class MemoryLr24ByteStreamLink implements Lr24ByteStreamLink {
  MemoryLr24ByteStreamLink({this.isOpen = true});

  @override
  bool isOpen;

  final StreamController<Uint8List> _received =
      StreamController<Uint8List>.broadcast(sync: true);
  MemoryLr24ByteStreamLink? _peer;

  @override
  Stream<Uint8List> get received => _received.stream;

  void connectPeer(MemoryLr24ByteStreamLink peer) {
    _peer = peer;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (!isOpen) throw StateError('LR24 link is closed');
    final peer = _peer;
    if (peer == null || !peer.isOpen) {
      throw StateError('LR24 peer link is unavailable');
    }
    peer._received.add(Uint8List.fromList(bytes));
  }

  Future<void> close() async {
    isOpen = false;
    await _received.close();
  }
}
