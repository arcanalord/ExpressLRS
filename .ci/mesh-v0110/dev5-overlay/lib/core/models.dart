enum DeliveryState {
  queued,
  sending,
  waitingAck,
  delivered,
  noRoute,
  retryWait,
  expired,
  failed,
  cancelled,
}

extension DeliveryStateX on DeliveryState {
  bool get isTerminal => switch (this) {
    DeliveryState.delivered ||
    DeliveryState.expired ||
    DeliveryState.failed ||
    DeliveryState.cancelled => true,
    _ => false,
  };
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
  });

  final String messageId;
  final String peerMmId;
  final String text;
  final bool outgoing;
  final DateTime createdAt;
  final String messageClass;
  final MapPoint? mapPoint;

  bool get isMapPoint => messageClass == 'map_point' && mapPoint != null;

  Map<String, Object?> toJson() => {
    'messageId': messageId,
    'peerMmId': peerMmId,
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
  final String messageClass;
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
