import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/domain/message.dart';
import 'package:mesh_messenger_best_v1/src/m02/delivery_engine.dart';
import 'package:mesh_messenger_best_v1/src/m03/transport_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m07/protector.dart';
import 'package:mesh_messenger_best_v1/src/m12/router.dart';

void main() {
  test('recipient ACK during submit cannot be downgraded by transport result',
      () async {
    late DeliveryEngine engine;
    final transport = _CallbackTransport(
      onSubmit: (packet) {
        engine.onRecipientAck(
          const RecipientAck(
            messageId: 'm-early-ack',
            recipientMmId: 'mm:bob',
            authenticated: true,
          ),
        );
      },
    );
    engine = DeliveryEngine(
      protector: const DevelopmentMessageProtector(localMmId: 'mm:alice'),
      router: const Lr24SingleRouteRouter(),
      transport: transport,
    );

    final record = await engine.sendText(
      recipientMmId: 'mm:bob',
      text: 'fast receipt',
      messageId: 'm-early-ack',
    );

    expect(record.state, DeliveryState.delivered);
    expect(engine.records['m-early-ack']?.state, DeliveryState.delivered);

    // Delivered retries are idempotent and do not put another frame on wire.
    final again = await engine.sendText(
      recipientMmId: 'mm:bob',
      text: 'fast receipt',
      messageId: 'm-early-ack',
    );
    expect(again.state, DeliveryState.delivered);
    expect(transport.submitCount, 1);
  });

  test('text path keeps one messageId and transport cannot mark Delivered',
      () async {
    final transport = MemoryLr24Adapter();
    final engine = DeliveryEngine(
      protector: const DevelopmentMessageProtector(),
      router: const Lr24SingleRouteRouter(),
      transport: transport,
    );

    final first = await engine.sendText(
      recipientMmId: 'mm:bob',
      text: 'hello',
      messageId: 'm-001',
    );
    expect(first.state, DeliveryState.sentToTransport);
    expect(transport.submitted, hasLength(1));
    expect(transport.submitted.single.idempotencyToken, 'm-001');

    final retry = await engine.sendText(
      recipientMmId: 'mm:bob',
      text: 'hello',
      messageId: 'm-001',
    );
    expect(retry.message.messageId, 'm-001');
    expect(transport.submitted, hasLength(2));
    expect(
      transport.submitted.map((packet) => packet.idempotencyToken).toSet(),
      {'m-001'},
    );
    expect(retry.state, isNot(DeliveryState.delivered));

    expect(
      engine.onRecipientAck(
        const RecipientAck(
          messageId: 'm-001',
          recipientMmId: 'mm:eve',
          authenticated: true,
        ),
      ),
      isFalse,
    );
    expect(retry.state, isNot(DeliveryState.delivered));

    expect(
      engine.onRecipientAck(
        const RecipientAck(
          messageId: 'm-001',
          recipientMmId: 'mm:bob',
          authenticated: false,
        ),
      ),
      isFalse,
    );
    expect(retry.state, isNot(DeliveryState.delivered));

    expect(
      engine.onRecipientAck(
        const RecipientAck(
          messageId: 'm-001',
          recipientMmId: 'mm:bob',
          authenticated: true,
        ),
      ),
      isTrue,
    );
    expect(retry.state, DeliveryState.delivered);
  });

  test('protected bytes cannot be mutated across M07 -> M12 boundary', () {
    final message = LogicalMessage(
      messageId: 'm-immutable',
      recipientMmId: 'mm:bob',
      text: 'secret',
    );
    final envelope = const DevelopmentMessageProtector().protect(message);
    final before = envelope.protectedBytes;
    final exposedEnvelopeBytes = envelope.protectedBytes;
    exposedEnvelopeBytes[0] ^= 0xff;
    expect(envelope.protectedBytes, before);

    final packet = const Lr24SingleRouteRouter().prepare(envelope);
    final packetBefore = packet.protectedBytes;
    final exposedPacketBytes = packet.protectedBytes;
    exposedPacketBytes[0] ^= 0xff;
    expect(packet.protectedBytes, packetBefore);
    expect(packet.protectedBytes, envelope.protectedBytes);
  });

  test('dedupe accepts one logical message once', () {
    final deduper = InboundDeduper();
    expect(deduper.accept('m-001'), isTrue);
    expect(deduper.accept('m-001'), isFalse);
    expect(deduper.accept('m-002'), isTrue);
  });
}


final class _CallbackTransport implements PreparedTransportAdapter {
  _CallbackTransport({required this.onSubmit});

  final void Function(PreparedTransportPacket packet) onSubmit;
  int submitCount = 0;

  @override
  String get id => 'lr24';

  @override
  bool get available => true;

  @override
  Stream<TransportInboundFrame> get inbound =>
      const Stream<TransportInboundFrame>.empty();

  @override
  Future<TransportSubmitResult> submit(PreparedTransportPacket packet) async {
    submitCount++;
    onSubmit(packet);
    return const TransportSubmitResult(TransportSubmitStatus.accepted);
  }
}
