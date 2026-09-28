enum DeliveryState {
  queued,
  sending,
  waitingAck,
  delivered,
  broadcasted,
  noRoute,
  retryWait,
  expired,
  failed,
  cancelled,
}

extension DeliveryStateX on DeliveryState {
  bool get isTerminal => switch (this) {
    DeliveryState.delivered ||
    DeliveryState.broadcasted ||
    DeliveryState.expired ||
    DeliveryState.failed ||
    DeliveryState.cancelled => true,
    _ => false,
  };
}

enum ConversationKind { channel, direct, group }

final class ConversationRef {
  const ConversationRef.channel(this.id) : kind = ConversationKind.channel;
  const ConversationRef.direct(this.id) : kind = ConversationKind.direct;
  const ConversationRef.group(this.id) : kind = ConversationKind.group;

  final ConversationKind kind;
  final String id;

  String get key => '${kind.name}:$id';

  static ConversationRef fromKey(String key) {
    if (key.startsWith('channel:')) {
      return ConversationRef.channel(key.substring('channel:'.length));
    }
    if (key.startsWith('direct:')) {
      return ConversationRef.direct(key.substring('direct:'.length));
    }
    if (key.startsWith('group:')) {
      return ConversationRef.group(key.substring('group:'.length));
    }
    throw FormatException('Unknown conversation key: $key');
  }
}

String channelTargetKey(String channelId) => 'channel:$channelId';
bool isChannelTargetKey(String value) => value.startsWith('channel:');
String? channelIdFromTargetKey(String value) =>
    isChannelTargetKey(value) ? value.substring('channel:'.length) : null;


String groupTargetKey(String groupId, String memberMmId) =>
    'group:$groupId@$memberMmId';
bool isGroupTargetKey(String value) => value.startsWith('group:') && value.contains('@');
String? groupIdFromTargetKey(String value) {
  if (!isGroupTargetKey(value)) return null;
  final body = value.substring('group:'.length);
  return body.substring(0, body.indexOf('@'));
}
String? groupMemberFromTargetKey(String value) {
  if (!isGroupTargetKey(value)) return null;
  final body = value.substring('group:'.length);
  return body.substring(body.indexOf('@') + 1);
}

final class GroupDefinition {
  const GroupDefinition({
    required this.groupId,
    required this.displayName,
    required this.creatorMmId,
    required this.memberMmIds,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String groupId;
  final String displayName;
  final String creatorMmId;
  final List<String> memberMmIds;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool contains(String mmId) => memberMmIds.contains(mmId);

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'displayName': displayName,
    'creatorMmId': creatorMmId,
    'memberMmIds': memberMmIds,
    'revision': revision,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory GroupDefinition.fromJson(Map<String, dynamic> json) => GroupDefinition(
    groupId: json['groupId'] as String,
    displayName: json['displayName'] as String,
    creatorMmId: json['creatorMmId'] as String,
    memberMmIds: (json['memberMmIds'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false),
    revision: (json['revision'] as num?)?.toInt() ?? 1,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

final class GroupReceiptRecord {
  const GroupReceiptRecord({
    required this.messageId,
    required this.groupId,
    required this.memberMmId,
    required this.receivedAt,
  });

  final String messageId;
  final String groupId;
  final String memberMmId;
  final DateTime receivedAt;

  Map<String, Object?> toJson() => {
    'messageId': messageId,
    'groupId': groupId,
    'memberMmId': memberMmId,
    'receivedAt': receivedAt.toIso8601String(),
  };

  factory GroupReceiptRecord.fromJson(Map<String, dynamic> json) =>
      GroupReceiptRecord(
        messageId: json['messageId'] as String,
        groupId: json['groupId'] as String,
        memberMmId: json['memberMmId'] as String,
        receivedAt: DateTime.parse(json['receivedAt'] as String),
      );
}

final class Contact {
  const Contact({
    required this.mmId,
    required this.displayName,
    this.verified = false,
    this.identityPublicKey,
    this.agreementPublicKey,
    this.fingerprint,
    this.verifiedAt,
    this.meshtasticNodeNum,
    this.ep2NodeId,
  });
  final String mmId;
  final String displayName;
  final bool verified;
  final String? identityPublicKey;
  final String? agreementPublicKey;
  final String? fingerprint;
  final DateTime? verifiedAt;
  final int? meshtasticNodeNum;
  final int? ep2NodeId;

  Map<String, Object?> toJson() => {
    'mmId': mmId,
    'displayName': displayName,
    'verified': verified,
    'identityPublicKey': identityPublicKey,
    'agreementPublicKey': agreementPublicKey,
    'fingerprint': fingerprint,
    'verifiedAt': verifiedAt?.toIso8601String(),
    'meshtasticNodeNum': meshtasticNodeNum,
    'ep2NodeId': ep2NodeId,
  };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    mmId: json['mmId'] as String,
    displayName: json['displayName'] as String,
    verified: json['verified'] as bool? ?? false,
    identityPublicKey: json['identityPublicKey'] as String?,
    agreementPublicKey: json['agreementPublicKey'] as String?,
    fingerprint: json['fingerprint'] as String?,
    verifiedAt: json['verifiedAt'] == null
        ? null
        : DateTime.tryParse(json['verifiedAt'] as String),
    meshtasticNodeNum: (json['meshtasticNodeNum'] as num?)?.toInt(),
    ep2NodeId: (json['ep2NodeId'] as num?)?.toInt(),
  );
}

final class MapPoint {
  const MapPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.label = '',
    this.note = '',
  });

  final String id;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String label;
  final String note;

  Map<String, Object?> toJson() => {
    'id': id,
    'lat': latitude,
    'lon': longitude,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
    'note': note,
  };

  factory MapPoint.fromJson(Map<String, dynamic> json) => MapPoint(
    id: json['id'] as String,
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lon'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    label: json['label'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );
}

final class ConversationMessage {
  const ConversationMessage({
    required this.messageId,
    required this.peerMmId,
    required this.text,
    required this.outgoing,
    required this.createdAt,
    this.messageClass = 'text',
    this.mapPoint,
    this.conversationKey,
    this.senderMmId,
  });

  final String messageId;
  final String peerMmId;
  final String text;
  final bool outgoing;
  final DateTime createdAt;
  final String messageClass;
  final MapPoint? mapPoint;
  final String? conversationKey;
  final String? senderMmId;

  bool get isMapPoint => messageClass == 'map_point' && mapPoint != null;
  String get effectiveConversationKey =>
      conversationKey ?? 'direct:$peerMmId';

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'messageId': messageId,
    'peerMmId': peerMmId,
    'conversationKey': effectiveConversationKey,
    'senderMmId': senderMmId,
    'text': text,
    'outgoing': outgoing,
    'createdAt': createdAt.toIso8601String(),
    'messageClass': messageClass,
    'mapPoint': mapPoint?.toJson(),
  };

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    final rawPoint = json['mapPoint'];
    return ConversationMessage(
      messageId: json['messageId'] as String,
      peerMmId: json['peerMmId'] as String,
      text: json['text'] as String? ?? '',
      outgoing: json['outgoing'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      messageClass: json['messageClass'] as String? ?? 'text',
      conversationKey: json['conversationKey'] as String?,
      senderMmId: json['senderMmId'] as String?,
      mapPoint: rawPoint is Map<String, dynamic>
          ? MapPoint.fromJson(rawPoint)
          : rawPoint is Map
          ? MapPoint.fromJson(rawPoint.cast<String, dynamic>())
          : null,
    );
  }
}

final class DeliveryEnvelope {
  const DeliveryEnvelope({
    required this.messageId,
    required this.recipientMmId,
    this.deliveryId,
    required this.messageClass,
    required this.payload,
    required this.createdAt,
    required this.expiresAt,
    required this.priority,
    required this.state,
    this.selectedTransportId,
    this.lastError,
    this.attempts = 0,
    this.nextRetryAt,
  });

  final String messageId;
  final String recipientMmId;
  final String? deliveryId;
  final int? groupRevision;
  String get effectiveDeliveryId => deliveryId ?? messageId;
  final String messageClass;

  bool get isChannel => isChannelTargetKey(recipientMmId);
  String? get channelId => channelIdFromTargetKey(recipientMmId);
  bool get isGroup => isGroupTargetKey(recipientMmId);
  String? get groupId => groupIdFromTargetKey(recipientMmId);
  String? get groupMemberMmId => groupMemberFromTargetKey(recipientMmId);
  final String payload;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int priority;
  final DeliveryState state;
  final String? selectedTransportId;
  final String? lastError;
  final int attempts;
  final DateTime? nextRetryAt;

  Map<String, Object?> toJson() => {
    'messageId': messageId,
    'deliveryId': effectiveDeliveryId,
    'groupRevision': groupRevision,
    'recipientMmId': recipientMmId,
    'messageClass': messageClass,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'priority': priority,
    'state': state.name,
    'selectedTransportId': selectedTransportId,
    'lastError': lastError,
    'attempts': attempts,
    'nextRetryAt': nextRetryAt?.toIso8601String(),
  };

  factory DeliveryEnvelope.fromJson(Map<String, dynamic> json) =>
      DeliveryEnvelope(
        messageId: json['messageId'] as String,
        deliveryId: json['deliveryId'] as String?,
        groupRevision: (json['groupRevision'] as num?)?.toInt(),
        recipientMmId: json['recipientMmId'] as String,
        messageClass: json['messageClass'] as String,
        payload: json['payload'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        priority: (json['priority'] as num).toInt(),
        state: DeliveryState.values.byName(json['state'] as String),
        selectedTransportId: json['selectedTransportId'] as String?,
        lastError: json['lastError'] as String?,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        nextRetryAt: json['nextRetryAt'] == null
            ? null
            : DateTime.parse(json['nextRetryAt'] as String),
      );

  DeliveryEnvelope copyWith({
    DeliveryState? state,
    String? selectedTransportId,
    bool clearSelectedTransport = false,
    String? lastError,
    bool clearLastError = false,
    int? attempts,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
  }) => DeliveryEnvelope(
    messageId: messageId,
    deliveryId: deliveryId,
    groupRevision: groupRevision,
    recipientMmId: recipientMmId,
    messageClass: messageClass,
    payload: payload,
    createdAt: createdAt,
    expiresAt: expiresAt,
    priority: priority,
    state: state ?? this.state,
    selectedTransportId: clearSelectedTransport
        ? null
        : selectedTransportId ?? this.selectedTransportId,
    lastError: clearLastError ? null : lastError ?? this.lastError,
    attempts: attempts ?? this.attempts,
    nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
  );
}
