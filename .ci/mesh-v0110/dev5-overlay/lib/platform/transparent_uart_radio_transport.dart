import 'dart:async';
import 'dart:typed_data';

import '../core/delivery.dart';
import '../core/file_transfer_core.dart';
import '../core/m07_security.dart';
import '../core/models.dart';
import 'android_usb_serial_bridge.dart';
import 'file1_transport_bridge.dart';
import 'mm_serial_codec.dart';
import 'm05_transport_qos_adapter.dart';

sealed class TransparentUartRadioEvent {
  const TransparentUartRadioEvent();
}

final class TransparentUartStateEvent extends TransparentUartRadioEvent {
  const TransparentUartStateEvent(this.state, {this.error});
  final String state;
  final String? error;
}

final class TransparentUartIncomingMessage extends TransparentUartRadioEvent {
  const TransparentUartIncomingMessage({
    required this.messageId,
    required this.fromMmId,
    required this.messageClass,
    required this.payload,
  });

  final String messageId;
  final String fromMmId;
  final String messageClass;
  final String payload;
}

final class TransparentUartRecipientAck extends TransparentUartRadioEvent {
  const TransparentUartRecipientAck({
    required this.messageId,
    required this.fromMmId,
  });

  final String messageId;
  final String fromMmId;
}

final class TransparentUartIncomingChannelMessage
    extends TransparentUartRadioEvent {
  const TransparentUartIncomingChannelMessage({
    required this.messageId,
    required this.fromMmId,
    required this.channelId,
    required this.messageClass,
    required this.payload,
  });

  final String messageId;
  final String fromMmId;
  final String channelId;
  final String messageClass;
  final String payload;
}

final class TransparentUartChannelReceipt extends TransparentUartRadioEvent {
  const TransparentUartChannelReceipt({
    required this.messageId,
    required this.fromMmId,
    required this.channelId,
  });

  final String messageId;
  final String fromMmId;
  final String channelId;
}



final class TransparentUartPeerDiscovered extends TransparentUartRadioEvent {
  const TransparentUartPeerDiscovered({
    required this.peerMmId,
    required this.label,
    required this.capabilities,
  });

  final String peerMmId;
  final String label;
  final Set<String> capabilities;
}

final class TransparentUartGroupDescriptor extends TransparentUartRadioEvent {
  const TransparentUartGroupDescriptor({
    required this.descriptor,
    required this.fromMmId,
  });

  final GroupDefinition descriptor;
  final String fromMmId;
}

final class TransparentUartIncomingGroupMessage
    extends TransparentUartRadioEvent {
  const TransparentUartIncomingGroupMessage({
    required this.messageId,
    required this.fromMmId,
    required this.groupId,
    required this.membershipRevision,
    required this.messageClass,
    required this.payload,
  });

  final String messageId;
  final String fromMmId;
  final String groupId;
  final int membershipRevision;
  final String messageClass;
  final String payload;
}

final class TransparentUartGroupReceipt extends TransparentUartRadioEvent {
  const TransparentUartGroupReceipt({
    required this.messageId,
    required this.fromMmId,
    required this.groupId,
  });

  final String messageId;
  final String fromMmId;
  final String groupId;
}

final class TransparentUartProbeResult extends TransparentUartRadioEvent {
  const TransparentUartProbeResult({
    required this.peerMmId,
    required this.rttMillis,
  });

  final String peerMmId;
  final int rttMillis;
}

final class TransparentUartFileReceived extends TransparentUartRadioEvent {
  const TransparentUartFileReceived({
    required this.transferId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String transferId;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

final class TransparentUartFileProgress extends TransparentUartRadioEvent {
  const TransparentUartFileProgress({
    required this.transferId,
    required this.state,
    required this.ackedChunks,
    required this.totalChunks,
    this.failureReason,
  });

  final String transferId;
  final String state;
  final int ackedChunks;
  final int totalChunks;
  final String? failureReason;

  double get fraction =>
      totalChunks == 0 ? 1 : ackedChunks / totalChunks;
}

final class TransparentUartStatsEvent extends TransparentUartRadioEvent {
  const TransparentUartStatsEvent({
    required this.txBytes,
    required this.rxBytes,
    required this.txFrames,
    required this.rxFrames,
    required this.badFrames,
  });

  final int txBytes;
  final int rxBytes;
  final int txFrames;
  final int rxFrames;
  final int badFrames;
}

final class _PendingProbe {
  _PendingProbe(this.started, this.completer, this.timer);
  final DateTime started;
  final Completer<Duration> completer;
  final Timer timer;
}

/// MessageTransport for stock transparent UART radios such as MicoAir LR24-F.
///
/// The modem is not probed or reflashed. It only carries MM-SERIAL/1 bytes.
final class TransparentUartRadioTransport implements MessageTransport {
  TransparentUartRadioTransport({
    required AndroidUsbSerialBridge bridge,
    required this.ownMmId,
    this.ownLabel = '',
  }) : _bridge = bridge {
    _qos = M05TransportQosAdapter(
      writeRaw: _writeRawFrame,
      writeRawFile1: _writeRawFile1,
    );
    _file1 = File1TransportBridge(
      sendBytes: _qos.sendFile1,
      onReceived: (received) {
        _events.add(
          TransparentUartFileReceived(
            transferId: received.manifest.transferId,
            fileName: received.manifest.fileName,
            mimeType: received.manifest.mimeType,
            bytes: received.bytes,
          ),
        );
      },
      onProgress: (progress) {
        _events.add(
          TransparentUartFileProgress(
            transferId: progress.transferId,
            state: progress.state.name,
            ackedChunks: progress.ackedChunks,
            totalChunks: progress.totalChunks,
            failureReason: progress.failureReason,
          ),
        );
      },
    );
  }

  final AndroidUsbSerialBridge _bridge;
  late final M05TransportQosAdapter _qos;
  late final File1TransportBridge _file1;
  final String ownMmId;
  final String ownLabel;
  final Set<String> _discoveredPeerMmIds = <String>{};
  final MmSerialCodec _codec = MmSerialCodec();
  final StreamController<TransparentUartRadioEvent> _events =
      StreamController<TransparentUartRadioEvent>.broadcast();
  StreamSubscription<AndroidUsbSerialEvent>? _subscription;
  final Map<String, _PendingProbe> _probes = <String, _PendingProbe>{};

  String state = 'disconnected';
  String? lastError;
  int? deviceId;
  int baudRate = 57600;
  int txBytes = 0;
  int rxBytes = 0;
  int txFrames = 0;
  int rxFrames = 0;

  Stream<TransparentUartRadioEvent> get events => _events.stream;

  @override
  String get id => 'lr24-usb';

  @override
  bool get isAvailable => state == 'ready';

  int get badFrames => _codec.badFrames;

  Future<void> connect(int id, {int baudRate = 57600}) async {
    await _subscription?.cancel();
    _subscription = _bridge.events.listen(_onBridgeEvent);
    _codec.reset();
    _failProbes(StateError('LR24 reconnect'));
    txBytes = 0;
    rxBytes = 0;
    txFrames = 0;
    rxFrames = 0;
    lastError = null;
    deviceId = id;
    this.baudRate = baudRate;
    state = 'connecting';
    _events.add(const TransparentUartStateEvent('connecting'));
    try {
      await _bridge.connect(id, baudRate: baudRate);
    } catch (error) {
      state = 'error';
      lastError = error.toString();
      _events.add(TransparentUartStateEvent('error', error: lastError));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _bridge.disconnect();
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _codec.reset();
      _failProbes(StateError('LR24 disconnected'));
      deviceId = null;
      state = 'disconnected';
      _events.add(const TransparentUartStateEvent('disconnected'));
    }
  }

  @override
  Future<TransportSendResult> send(DeliveryEnvelope envelope) async {
    if (!isAvailable) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LR24_NOT_READY',
      );
    }
    final targetMmId =
        envelope.isGroup ? envelope.groupMemberMmId : envelope.recipientMmId;
    if (!envelope.isChannel &&
        targetMmId != null &&
        _discoveredPeerMmIds.isNotEmpty &&
        !_discoveredPeerMmIds.contains(targetMmId)) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LR24_PEER_NOT_REACHABLE',
      );
    }
    if (envelope.messageClass != 'text' &&
        envelope.messageClass != 'map_point' &&
        envelope.messageClass != m07DirectEnvelopeClass) {
      return const TransportSendResult(
        TransportSendStatus.unavailable,
        detail: 'LR24_CLASS_UNSUPPORTED',
      );
    }
    final frame = envelope.isChannel
        ? <String, Object?>{
            'v': 1,
            'p': 'MMRP/1',
            'k': 'channel_data',
            'id': envelope.messageId,
            'from': ownMmId,
            'to': '*',
            'channel': envelope.channelId,
            'class': envelope.messageClass,
            'q': envelope.priority,
            'payload': envelope.payload,
          }
        : envelope.isGroup
        ? <String, Object?>{
            'v': 1,
            'p': 'MMRP/1',
            'k': 'group_data',
            'id': envelope.messageId,
            'from': ownMmId,
            'to': envelope.groupMemberMmId,
            'group': envelope.groupId,
            'rev': envelope.groupRevision ?? 1,
            'class': envelope.messageClass,
            'q': envelope.priority,
            'payload': envelope.payload,
          }
        : <String, Object?>{
            'v': 1,
            'p': 'MMRP/1',
            'k': 'data',
            'id': envelope.messageId,
            'from': ownMmId,
            'to': envelope.recipientMmId,
            'class': envelope.messageClass,
            'q': envelope.priority,
            'payload': envelope.payload,
          };
    try {
      await _writeFrame(frame);
      return const TransportSendResult(TransportSendStatus.accepted);
    } catch (error) {
      return TransportSendResult(
        TransportSendStatus.rejected,
        detail: 'LR24_WRITE_FAILED:' + error.toString(),
      );
    }
  }


  Future<void> sendFilePlan(FileTransferPlan plan) {
    if (!isAvailable) {
      return Future<void>.error(StateError('LR24_NOT_READY'));
    }
    return _file1.send(plan);
  }

  Future<bool> cancelFileTransfer(String transferId) =>
      _file1.cancel(transferId);

  Future<void> discoverPeers() async {
    if (!isAvailable) return;
    await _writeFrame(<String, Object?>{
      'v': 1,
      'p': 'MMRP/1',
      'k': 'hello',
      'from': ownMmId,
      'to': '*',
      'label': ownLabel,
      'caps': const <String>['DIRECT/1', 'CHANNEL/1', 'GROUP/1'],
    });
  }

  Future<void> sendGroupDescriptor({
    required GroupDefinition descriptor,
    required String toMmId,
  }) async {
    if (!isAvailable) return;
    await _writeFrame(<String, Object?>{
      'v': 1,
      'p': 'MMRP/1',
      'k': 'group_descriptor',
      'from': ownMmId,
      'to': toMmId,
      'group': descriptor.groupId,
      'name': descriptor.displayName,
      'creator': descriptor.creatorMmId,
      'members': descriptor.memberMmIds,
      'rev': descriptor.revision,
      'createdAt': descriptor.createdAt.toIso8601String(),
      'updatedAt': descriptor.updatedAt.toIso8601String(),
    });
  }

  Future<void> acknowledgeIncoming({
    required String messageId,
    required String toMmId,
  }) =>
      _writeFrame(<String, Object?>{
        'v': 1,
        'p': 'MMRP/1',
        'k': 'ack',
        'id': messageId,
        'from': ownMmId,
        'to': toMmId,
      });

  Future<void> acknowledgeChannelIncoming({
    required String messageId,
    required String channelId,
    required String toMmId,
  }) async {
    final jitterMs = 50 + (DateTime.now().microsecondsSinceEpoch % 451);
    await Future<void>.delayed(Duration(milliseconds: jitterMs));
    if (!isAvailable) return;
    await _writeFrame(<String, Object?>{
      'v': 1,
      'p': 'MMRP/1',
      'k': 'channel_receipt',
      'id': messageId,
      'from': ownMmId,
      'to': toMmId,
      'channel': channelId,
    });
  }


  Future<void> acknowledgeGroupIncoming({
    required String messageId,
    required String groupId,
    required String toMmId,
  }) => _writeFrame(<String, Object?>{
    'v': 1,
    'p': 'MMRP/1',
    'k': 'group_receipt',
    'id': messageId,
    'from': ownMmId,
    'to': toMmId,
    'group': groupId,
  });

  Future<Duration> probe(
    String peerMmId, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!isAvailable) throw StateError('LR24_NOT_READY');
    final nonce = DateTime.now().microsecondsSinceEpoch.toString() +
        '-' +
        (_probes.length + 1).toString();
    final completer = Completer<Duration>();
    late final Timer timer;
    timer = Timer(timeout, () {
      final pending = _probes.remove(nonce);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          TimeoutException('LR24 probe timeout', timeout),
        );
      }
    });
    _probes[nonce] = _PendingProbe(DateTime.now(), completer, timer);
    try {
      await _writeFrame(<String, Object?>{
        'v': 1,
        'p': 'MMRP/1',
        'k': 'ping',
        'n': nonce,
        'from': ownMmId,
        'to': peerMmId,
      });
    } catch (error, stackTrace) {
      final pending = _probes.remove(nonce);
      pending?.timer.cancel();
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  Future<void> _writeFrame(Map<String, Object?> frame) => _qos.send(frame);

  Future<void> _writeRawFrame(Map<String, Object?> frame) async {
    final bytes = _codec.encode(frame);
    await _bridge.write(bytes);
    txBytes += bytes.length;
    txFrames++;
    _emitStats();
  }

  Future<void> _writeRawFile1(Uint8List payload) async {
    final bytes = _codec.encodeBinary(
      payload,
      tag: MmSerialCodec.file1BinaryTag,
    );
    await _bridge.write(bytes);
    txBytes += bytes.length;
    txFrames++;
    _emitStats();
  }

  void _onBridgeEvent(AndroidUsbSerialEvent event) {
    if (event is AndroidUsbSerialState) {
      final next = (event.status['state'] ?? '').toString().trim().toLowerCase();
      final error = event.status['error']?.toString();
      if (next == 'ready' || next == 'connected') {
        state = 'ready';
        lastError = null;
        _events.add(const TransparentUartStateEvent('ready'));
      } else if (next == 'permission') {
        state = 'permission';
        _events.add(const TransparentUartStateEvent('permission'));
      } else if (next == 'permission_denied' || next == 'error') {
        state = 'error';
        lastError = error ?? next;
        _events.add(TransparentUartStateEvent('error', error: lastError));
      } else if (next == 'offline' ||
          next == 'disconnected' ||
          next == 'detached') {
        state = 'disconnected';
        _codec.reset();
        _failProbes(StateError('LR24 disconnected'));
        _events.add(const TransparentUartStateEvent('disconnected'));
      }
      return;
    }

    if (event is AndroidUsbSerialBytes) {
      rxBytes += event.bytes.length;
      final beforeBad = _codec.badFrames;
      final packets = _codec.feedPackets(Uint8List.fromList(event.bytes));
      if (_codec.badFrames != beforeBad) _emitStats();
      for (final packet in packets) {
        rxFrames++;
        if (packet is MmSerialJsonPacket) {
          _handleFrame(packet.frame);
        } else if (packet is MmSerialBinaryPacket &&
            packet.tag == MmSerialCodec.file1BinaryTag) {
          unawaited(_file1.handleIncoming(packet.payload));
        }
      }
      _emitStats();
    }
  }

  void _handleFrame(Map<String, dynamic> frame) {
    if (frame['p'] != 'MMRP/1' || frame['v'] != 1) return;
    final to = (frame['to'] ?? '').toString().trim();
    if (to.isNotEmpty && to != ownMmId && to != '*') return;
    final from = (frame['from'] ?? '').toString().trim();
    if (from.isEmpty || from == ownMmId) return;
    final kind = (frame['k'] ?? '').toString().trim();

    switch (kind) {

      case 'hello':
        _discoveredPeerMmIds.add(from);
        final label = (frame['label'] ?? '').toString().trim();
        final rawCaps = frame['caps'];
        final caps = rawCaps is List
            ? rawCaps.map((e) => e.toString()).toSet()
            : <String>{};
        _events.add(
          TransparentUartPeerDiscovered(
            peerMmId: from,
            label: label,
            capabilities: caps,
          ),
        );
        unawaited(
          _writeFrame(<String, Object?>{
            'v': 1,
            'p': 'MMRP/1',
            'k': 'hello_reply',
            'from': ownMmId,
            'to': from,
            'label': ownLabel,
            'caps': const <String>['DIRECT/1', 'CHANNEL/1', 'GROUP/1'],
          }),
        );
      case 'hello_reply':
        _discoveredPeerMmIds.add(from);
        final label = (frame['label'] ?? '').toString().trim();
        final rawCaps = frame['caps'];
        final caps = rawCaps is List
            ? rawCaps.map((e) => e.toString()).toSet()
            : <String>{};
        _events.add(
          TransparentUartPeerDiscovered(
            peerMmId: from,
            label: label,
            capabilities: caps,
          ),
        );
      case 'group_descriptor':
        final groupId = (frame['group'] ?? '').toString().trim();
        final name = (frame['name'] ?? '').toString().trim();
        final creator = (frame['creator'] ?? '').toString().trim();
        final rawMembers = frame['members'];
        final revision = (frame['rev'] as num?)?.toInt() ?? 0;
        final createdAt = DateTime.tryParse(
          (frame['createdAt'] ?? '').toString(),
        );
        final updatedAt = DateTime.tryParse(
          (frame['updatedAt'] ?? '').toString(),
        );
        if (groupId.isNotEmpty &&
            name.isNotEmpty &&
            creator.isNotEmpty &&
            rawMembers is List &&
            revision > 0 &&
            createdAt != null &&
            updatedAt != null) {
          _events.add(
            TransparentUartGroupDescriptor(
              fromMmId: from,
              descriptor: GroupDefinition(
                groupId: groupId,
                displayName: name,
                creatorMmId: creator,
                memberMmIds: rawMembers
                    .map((e) => e.toString())
                    .toList(growable: false),
                revision: revision,
                createdAt: createdAt.toUtc(),
                updatedAt: updatedAt.toUtc(),
              ),
            ),
          );
        }
      case 'ack':
        final id = (frame['id'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          _events.add(
            TransparentUartRecipientAck(messageId: id, fromMmId: from),
          );
        }
      case 'data':
        final id = (frame['id'] ?? '').toString().trim();
        final messageClass = (frame['class'] ?? '').toString().trim();
        final payload = frame['payload'];
        if (id.isNotEmpty &&
            messageClass.isNotEmpty &&
            payload is String) {
          _events.add(
            TransparentUartIncomingMessage(
              messageId: id,
              fromMmId: from,
              messageClass: messageClass,
              payload: payload,
            ),
          );
        }
      case 'channel_data':
        final id = (frame['id'] ?? '').toString().trim();
        final channelId = (frame['channel'] ?? '').toString().trim();
        final messageClass = (frame['class'] ?? '').toString().trim();
        final payload = frame['payload'];
        if (id.isNotEmpty &&
            channelId.isNotEmpty &&
            messageClass.isNotEmpty &&
            payload is String) {
          _events.add(
            TransparentUartIncomingChannelMessage(
              messageId: id,
              fromMmId: from,
              channelId: channelId,
              messageClass: messageClass,
              payload: payload,
            ),
          );
        }
      case 'channel_receipt':
        final id = (frame['id'] ?? '').toString().trim();
        final channelId = (frame['channel'] ?? '').toString().trim();
        if (id.isNotEmpty && channelId.isNotEmpty) {
          _events.add(
            TransparentUartChannelReceipt(
              messageId: id,
              fromMmId: from,
              channelId: channelId,
            ),
          );
        }

      case 'group_data':
        final id = (frame['id'] ?? '').toString().trim();
        final groupId = (frame['group'] ?? '').toString().trim();
        final revision = (frame['rev'] as num?)?.toInt() ?? 1;
        final messageClass = (frame['class'] ?? '').toString().trim();
        final payload = frame['payload'];
        if (id.isNotEmpty &&
            groupId.isNotEmpty &&
            messageClass.isNotEmpty &&
            payload is String) {
          _events.add(
            TransparentUartIncomingGroupMessage(
              messageId: id,
              fromMmId: from,
              groupId: groupId,
              membershipRevision: revision,
              messageClass: messageClass,
              payload: payload,
            ),
          );
        }
      case 'group_receipt':
        final id = (frame['id'] ?? '').toString().trim();
        final groupId = (frame['group'] ?? '').toString().trim();
        if (id.isNotEmpty && groupId.isNotEmpty) {
          _events.add(
            TransparentUartGroupReceipt(
              messageId: id,
              fromMmId: from,
              groupId: groupId,
            ),
          );
        }
      case 'ping':
        final nonce = (frame['n'] ?? '').toString().trim();
        if (nonce.isNotEmpty) {
          unawaited(
            _writeFrame(<String, Object?>{
              'v': 1,
              'p': 'MMRP/1',
              'k': 'pong',
              'n': nonce,
              'from': ownMmId,
              'to': from,
            }),
          );
        }
      case 'pong':
        final nonce = (frame['n'] ?? '').toString().trim();
        final pending = _probes.remove(nonce);
        if (pending != null) {
          pending.timer.cancel();
          final elapsed = DateTime.now().difference(pending.started);
          if (!pending.completer.isCompleted) {
            pending.completer.complete(elapsed);
          }
          _events.add(
            TransparentUartProbeResult(
              peerMmId: from,
              rttMillis: elapsed.inMilliseconds,
            ),
          );
        }
    }
  }

  void _emitStats() {
    _events.add(
      TransparentUartStatsEvent(
        txBytes: txBytes,
        rxBytes: rxBytes,
        txFrames: txFrames,
        rxFrames: rxFrames,
        badFrames: badFrames,
      ),
    );
  }

  void _failProbes(Object error) {
    for (final pending in _probes.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _probes.clear();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _failProbes(StateError('LR24 transport closed'));
    _file1.close();
    await _events.close();
  }
}
