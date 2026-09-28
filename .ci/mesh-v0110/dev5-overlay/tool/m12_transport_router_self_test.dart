import 'dart:io';

import '../lib/core/m12_transport_router.dart';
import '../lib/platform/internet_relay_contract.dart';

void _expect(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  const router = M12TransportRouter();

  final relayCaps = InternetRelayCapabilities.fromJson({
    'protocol': 'MM-RELAY/1',
    'maxCiphertextBytes': 64 * 1024,
    'maxPendingPacketsPerMailbox': 128,
    'maxPendingCiphertextBytesPerMailbox': 4 * 1024 * 1024,
    'defaultTtlSeconds': 7 * 24 * 60 * 60,
    'maxTtlSeconds': 14 * 24 * 60 * 60,
  });
  _expect(relayCaps.protocol == 'MM-RELAY/1', 'relay protocol mismatch');
  relayCaps.validateCiphertextLength(64 * 1024);

  var unsupportedRejected = false;
  try {
    InternetRelayCapabilities.fromJson({
      'protocol': 'MM-RELAY/2',
      'maxCiphertextBytes': 1,
      'maxPendingPacketsPerMailbox': 1,
      'maxPendingCiphertextBytesPerMailbox': 1,
      'defaultTtlSeconds': 1,
      'maxTtlSeconds': 1,
    });
  } on StateError {
    unsupportedRejected = true;
  }
  _expect(unsupportedRejected, 'unknown relay major was silently accepted');

  const logicalMessageId = 'm12-msg-1';
  final internet = relayCaps.asTransport(
    available: true,
    validatedInternet: true,
    metered: false,
    estimatedRttMs: 80,
  );
  const lan = TransportCapabilities(
    transportId: 'lan',
    transportClass: TransportClass.lan,
    available: false,
    supportsText: true,
    supportsAttachments: true,
    estimatedRttMs: 10,
  );
  const radio = TransportCapabilities(
    transportId: 'lr24',
    transportClass: TransportClass.radio,
    available: true,
    supportsText: true,
    supportsAttachments: false,
    estimatedRttMs: 180,
    healthScore: 85,
  );

  final first = router.plan(
    messageId: logicalMessageId,
    messageClass: 'text',
    transports: [lan, internet, radio],
  );
  _expect(first.primary?.transportId == 'internet-relay',
      'Internet Relay should be default text route when usable');
  _expect(first.messageId == logicalMessageId,
      'route planning changed logical message id');

  final handover = router.plan(
    messageId: logicalMessageId,
    messageClass: 'text',
    transports: [
      relayCaps.asTransport(
        available: false,
        validatedInternet: false,
        metered: false,
      ),
      radio,
    ],
  );
  _expect(handover.primary?.transportId == 'lr24',
      'radio failover was not selected');
  _expect(handover.messageId == logicalMessageId,
      'handover created a new logical message');

  final badWifiInternet = router.plan(
    messageId: logicalMessageId,
    messageClass: 'text',
    transports: [
      relayCaps.asTransport(
        available: true,
        validatedInternet: false,
        metered: false,
      ),
      radio,
    ],
  );
  _expect(badWifiInternet.primary?.transportId == 'lr24',
      'unvalidated Internet was treated as usable relay route');

  final attachment = router.plan(
    messageId: 'm12-file-1',
    messageClass: 'file',
    transports: [
      relayCaps.asTransport(
        available: true,
        validatedInternet: true,
        metered: true,
      ),
      const TransportCapabilities(
        transportId: 'lan-fast',
        transportClass: TransportClass.lan,
        available: true,
        supportsAttachments: true,
        estimatedThroughputBps: 8 * 1000 * 1000,
        estimatedRttMs: 12,
      ),
    ],
  );
  _expect(attachment.primary?.transportId == 'lan-fast',
      'unmetered fast attachment route was not preferred');

  final relayStored = RelayTransportResult(
    evidence: RelayTransportEvidence.stored,
    relayPacketId: 'rp-1',
  );
  _expect(!relayStored.isRecipientDelivered,
      'relay stored was incorrectly treated as Delivered');

  _expect(
    relayMetadataLooksOpaque({
      'mailboxHandle': 'mbx-random-1',
      'relayPacketId': 'rp-1',
      'expiry': 123456,
    }),
    'opaque relay metadata was rejected',
  );
  _expect(
    !relayMetadataLooksOpaque({
      'mailboxHandle': 'mbx-random-1',
      'mmId': 'mm:secret',
    }),
    'clear MM-ID was allowed into relay metadata',
  );

  stdout.writeln('MESH_MESSENGER_M12_RELAY_CONTRACT_PASS');
}
