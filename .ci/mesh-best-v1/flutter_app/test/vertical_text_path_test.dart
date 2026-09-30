import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_messenger_best_v1/src/domain/message.dart';
import 'package:mesh_messenger_best_v1/src/m02/delivery_engine.dart';
import 'package:mesh_messenger_best_v1/src/m03/transport_adapter.dart';
import 'package:mesh_messenger_best_v1/src/m07/protector.dart';
import 'package:mesh_messenger_best_v1/src/m12/router.dart';

void main() {
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
