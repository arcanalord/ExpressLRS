import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/app_build_info.dart';
import '../../core/app_storage.dart';
import '../../core/adaptive_link_profile.dart';
import '../../core/file_transfer_core.dart';
import '../../core/contact_card.dart';
import '../../core/diagnostic_snapshot.dart';
import '../../core/delivery.dart';
import '../../core/identity_crypto.dart';
import '../../core/m07_atomic_provider.dart';
import '../../core/m07_provider_state_store.dart';
import '../../core/m07_security.dart';
import '../../core/messenger_core.dart';
import '../../core/secure_core_policy.dart';
import '../../core/models.dart';
import '../../core/usb_profile_binding.dart';
import '../../platform/android_app_storage_crypto.dart';
import '../../platform/android_diagnostics_export_bridge.dart';
import '../../platform/android_local_network_bridge.dart';
import '../../platform/android_m07_direct_ratchet_engine.dart';
import '../../platform/android_secure_identity_bridge.dart';
import '../../platform/android_meshtastic_bridge.dart';
import '../../platform/android_usb_serial_bridge.dart';
import '../../platform/android_usb_mm_uart_host_link.dart';
import '../../platform/ep2_uart_transport.dart';
import '../../platform/mm_uart_external_radio_session.dart';
import '../../platform/mm_uart_hil_bench.dart';
import '../../platform/mm_uart_message_transport.dart';
import '../../platform/transparent_uart_radio_transport.dart';
import '../../platform/usb_profile_binding_store.dart';
import '../../platform/lan_transport.dart';
import '../../platform/meshtastic_transport.dart';

final class LanPairingSession {
  const LanPairingSession({
    required this.pairingId,
    required this.peerMmId,
    required this.peerLabel,
    required this.fingerprint,
    required this.identityPublicKey,
    required this.agreementPublicKey,
    required this.sas,
    required this.initiator,
    this.localConfirmed = false,
    this.remoteConfirmed = false,
  });

  final String pairingId;
  final String peerMmId;
  final String peerLabel;
  final String fingerprint;
  final List<int> identityPublicKey;
  final List<int> agreementPublicKey;
  final String sas;
  final bool initiator;
  final bool localConfirmed;
  final bool remoteConfirmed;

  LanPairingSession copyWith({bool? localConfirmed, bool? remoteConfirmed}) =>
      LanPairingSession(
        pairingId: pairingId,
        peerMmId: peerMmId,
        peerLabel: peerLabel,
        fingerprint: fingerprint,
        identityPublicKey: identityPublicKey,
        agreementPublicKey: agreementPublicKey,
        sas: sas,
        initiator: initiator,
        localConfirmed: localConfirmed ?? this.localConfirmed,
        remoteConfirmed: remoteConfirmed ?? this.remoteConfirmed,
      );
}

final class MeshAppController extends ChangeNotifier {
  MeshAppController._();

  late final MeshMessengerCore _core;
  late final LocalCryptoIdentity _identity;
  LanTransport? _lan;
  AndroidLocalNetworkBridge? _localNetworkBridge;
  MeshtasticTransport? _meshtastic;
  AndroidMeshtasticBridge? _androidBridge;
  AndroidUsbSerialBridge? _usbBridge;
  AndroidDiagnosticsExportBridge? _diagnosticsExportBridge;
  Ep2UartTransport? _ep2;
  MmUartExternalRadioSession? _externalRadioSession;
  MmUartMessageTransport? _externalRadio;
  MmUartHilBench? _radioHilBench;
  TransparentUartRadioTransport? _lr24;
  UsbProfileBindingStore? _usbProfileBindingStore;
  UsbProfileBinding? _usbProfileBinding;
  StreamSubscription<TransparentUartRadioEvent>? _lr24Sub;
  bool _mmUartActive = false;
  bool _lr24Active = false;
  StreamSubscription<DeliveryEnvelope>? _deliverySub;
  StreamSubscription<LanTransportEvent>? _lanSub;
  StreamSubscription<MeshtasticTransportEvent>? _meshtasticSub;
  StreamSubscription<AndroidMeshtasticEvent>? _androidSub;
  StreamSubscription<Ep2TransportEvent>? _ep2Sub;
  StreamSubscription<MmUartMessageTransportEvent>? _externalRadioSub;
  StreamSubscription<ExternalRadioSessionEvent>? _externalSessionSub;
  Timer? _maintenanceTimer;
  Future<void>? _shutdownFuture;
  bool _maintenanceBusy = false;
  bool _usbMaintenanceBusy = false;
  int _usbMaintenanceTick = 0;
  int _lr24DiscoveryTick = 0;

  bool initialized = false;
  bool busy = false;
  bool advancedMode = false;
  AppStorage? _appStorage;
  ConversationRef activeConversation = const ConversationRef.channel('general');
  String? selectedPeerMmId;
  List<Contact> contacts = const [];
  List<GroupDefinition> groups = const [];
  List<ConversationMessage> messages = const [];
  List<String> messageRequestPeerMmIds = const [];
  String? preparedFileName;
  int? preparedFileBytes;
  int? preparedFileChunks;
  String? preparedFileSha256;
  AdaptiveLinkProfile preparedFileProfile = AdaptiveLinkProfile.reliable;
  String? fileTransferNotice;
  String fileTransferState = 'idle';
  int fileTransferAckedChunks = 0;
  FileTransferPlan? _preparedFilePlan;
  bool fileTransferSending = false;

  double get fileTransferProgress {
    final total = preparedFileChunks ?? 0;
    if (total <= 0) return 0;
    return (fileTransferAckedChunks / total).clamp(0.0, 1.0);
  }

  bool get fileTransferCanRetry =>
      _preparedFilePlan != null &&
      !fileTransferSending &&
      (fileTransferState == 'failed' || fileTransferState == 'cancelled');
  bool get fileTransferPausedByUser => fileTransferState == 'pausedUser';
  bool get fileTransferWaitingRoute => fileTransferState == 'pausedLink';
  bool get fileTransferCanPause =>
      _preparedFilePlan != null &&
      fileTransferSending &&
      !fileTransferPausedByUser &&
      !fileTransferWaitingRoute;
  bool get fileTransferCanContinue =>
      _preparedFilePlan != null &&
      fileTransferSending &&
      fileTransferPausedByUser &&
      lr24Connected &&
      lr24PeerReachable;
  String? lastReceivedFileName;
  String? lastReceivedFilePath;
  final Map<String, DateTime> _peerLastSeen = <String, DateTime>{};
  final Map<String, String> _peerLabels = <String, String>{};
  final Map<String, Set<String>> _peerCapabilities = <String, Set<String>>{};
  final Map<String, Set<String>> _channelReceipts = <String, Set<String>>{};
  final Map<String, Set<String>> _groupReceipts = <String, Set<String>>{};
  MapPoint? requestedMapFocus;
  int mapFocusSerial = 0;

  String ownMmId = '';
  String ownDeviceLabel = '';
  String ownFingerprint = '';
  String ownIdentityPublicKey = '';
  String ownAgreementPublicKey = '';
  String identitySeedStorage = '';

  String get ownContactCardPayload => ContactCard(
    mmId: ownMmId,
    displayName: ownDeviceLabel.isEmpty ? 'Mesh Messenger' : ownDeviceLabel,
    fingerprint: ownFingerprint.isEmpty ? null : ownFingerprint,
    identityPublicKey: ownIdentityPublicKey.isEmpty
        ? null
        : ownIdentityPublicKey,
    agreementPublicKey: ownAgreementPublicKey.isEmpty
        ? null
        : ownAgreementPublicKey,
    radioNodeId: ep2LocalNode,
  ).encode();
  final Map<String, LanPairingSession> lanPairings =
      <String, LanPairingSession>{};
  String lanState = 'offline';
  String? lanError;
  String? lanNotice;
  Map<String, dynamic> lanPermission = const {};
  List<LanPeer> lanPeers = const [];
  List<String> lanLocalAddresses = const [];
  final List<String> lanLog = <String>[];
  final Map<String, int> lanRttMs = <String, int>{};
  final Set<String> lanProbePending = <String>{};

  String radioState = 'unavailable';
  String? radioError;
  String? lastRadioNotice;
  List<MeshtasticBleDevice> radioDevices = const [];
  Map<String, dynamic> radioPermissions = const {};
  Map<String, dynamic> radioDiagnostics = const {};
  final List<String> radioLog = <String>[];

  String ep2State = 'unavailable';
  String? ep2Error;
  int? ep2LocalNode;
  String? ep2Firmware;
  String? ep2Profile;
  String ep2Protocol = 'unknown';
  int? ep2Baud;
  int? ep2Rssi10;
  int? ep2Snr10;
  int? ep2RttMs;
  int? ep2TxCount;
  int? ep2RxCount;
  int? ep2LossCount;
  int? ep2RetryCount;
  String? ep2PingResult;
  String? ep2OtaSsid;
  String? ep2OtaPassword;
  String? ep2OtaUrl;
  String? ep2OtaNotice;
  String? ep2InfoNotice;
  String ep2DetectedProtocol = 'unknown';
  int ep2RxBytes = 0;
  int ep2TxBytes = 0;
  String ep2LastHex = '';
  List<UsbSerialDevice> ep2Devices = const [];
  final List<String> ep2Log = <String>[];
  int? ep2ConnectedDeviceId;
  bool radioHilRunning = false;
  String lr24State = 'disconnected';
  String? lr24Error;
  int? lr24ConnectedDeviceId;
  int lr24Baud = 57600;
  int lr24TxBytes = 0;
  int lr24RxBytes = 0;
  int lr24TxFrames = 0;
  int lr24RxFrames = 0;
  int lr24BadFrames = 0;
  int? lr24RttMs;
  String? lr24PeerMmId;
  final List<String> lr24Log = <String>[];
  int radioHilDone = 0;
  int radioHilTotal = 0;
  String? radioHilResult;
  String? radioHilError;

  bool get hasLocalNetworkPermissionBridge => _localNetworkBridge != null;
  bool get lanReady => _lan?.isAvailable ?? false;
  bool get lanPermissionGranted => lanPermission['granted'] == true;
  bool get lanPermissionRequired => lanPermission['required'] == true;
  bool get hasAndroidMeshtastic => _androidBridge != null;
  bool get radioConnected => _androidBridge?.connected ?? false;
  bool get hasEp2Uart => _usbBridge != null;
  bool get mmUartActive => _mmUartActive;
  bool get lr24Active => _lr24Active;
  bool get lr24Connected => _lr24?.isAvailable == true;
  bool get lr24PeerReachable => _lr24?.hasFreshPeers == true;
  bool get lr24SelectedPeerReachable {
    final peer = selectedPeerMmId;
    return peer != null && (_lr24?.isPeerFresh(peer) ?? false);
  }

  bool get ep2Connected =>
      (_externalRadio?.isAvailable ?? false) || (_ep2?.isAvailable ?? false);
  String? get externalRadioFamily =>
      _externalRadioSession?.snapshot().info?.radioFamily;
  String? get externalBoardId =>
      _externalRadioSession?.snapshot().info?.boardId;
  bool get externalRadioSupportsMmrp =>
      _externalRadioSession?.supportsMmrp == true;
  bool get radioHilAvailable => _radioHilBench?.isAvailable == true;
  int? get radioHilTargetNode {
    final contactNode = selectedContact?.ep2NodeId;
    if (contactNode != null) return contactNode;
    if (ep2LocalNode == 1) return 2;
    if (ep2LocalNode == 2) return 1;
    return null;
  }

  @visibleForTesting
  static Future<MeshAppController> createForWidgetTest({
    required Directory storageRoot,
  }) async {
    final controller = MeshAppController._();
    final storage = AppStorage(storageRoot);
    controller.ownMmId = 'mm:widget-test';
    controller.ownDeviceLabel = 'Widget Test';
    controller.ownFingerprint = 'widget-test';
    controller.identitySeedStorage = 'test-only';
    controller._core = MeshMessengerCore(
      ownMmId: controller.ownMmId,
      storage: storage,
      transports: const <MessageTransport>[],
    );
    await controller._core.restore();
    controller.contacts = await controller._core.contacts();
    controller.groups = await controller._core.groups();
    for (final receipt in await controller._core.groupReceipts()) {
      controller._groupReceipts
          .putIfAbsent(receipt.messageId, () => <String>{})
          .add(receipt.memberMmId);
    }
    controller.activeConversation = const ConversationRef.channel('general');
    controller.selectedPeerMmId = null;
    controller.messages = await controller._core.messagesForConversation(
      controller.activeConversation,
    );
    controller.initialized = true;
    return controller;
  }

  static Future<MeshAppController> create({
    Directory? storageRoot,
    bool startRuntime = true,
  }) async {
    final controller = MeshAppController._();
    AndroidLocalNetworkBridge? localNetworkBridge;
    AndroidMeshtasticBridge? bridge;
    AndroidUsbSerialBridge? usbBridge;
    Directory root;
    if (Platform.isAndroid) {
      localNetworkBridge = AndroidLocalNetworkBridge();
      bridge = AndroidMeshtasticBridge();
      usbBridge = AndroidUsbSerialBridge();
      controller._diagnosticsExportBridge =
          const AndroidDiagnosticsExportBridge();
      root = storageRoot ?? Directory(await bridge.appDataPath());
    } else {
      root =
          storageRoot ??
          Directory('${Directory.systemTemp.path}/mesh_messenger_flutter_dev');
    }
    await controller._init(
      root,
      localNetworkBridge,
      bridge,
      usbBridge,
      startRuntime,
    );
    return controller;
  }

  Future<void> _init(
    Directory root,
    AndroidLocalNetworkBridge? localNetworkBridge,
    AndroidMeshtasticBridge? bridge,
    AndroidUsbSerialBridge? usbBridge,
    bool startRuntime,
  ) async {
    _localNetworkBridge = localNetworkBridge;
    _androidBridge = bridge;
    _usbBridge = usbBridge;
    if (usbBridge != null) {
      _usbProfileBindingStore = UsbProfileBindingStore(root);
      _usbProfileBinding = await _usbProfileBindingStore!.load();
    }

    final securityPolicy = SecureCorePolicy.forBuild(isRelease: kReleaseMode);
    final storageCrypto =
        Platform.isAndroid ? AndroidAppStorageCrypto() : null;
    final storage = AppStorage(
      root,
      crypto: storageCrypto,
      requireEncryption: securityPolicy.requireEncryptedStorage,
    );
    await storage.migrateSensitiveStorage();
    _appStorage = storage;
    final uiPreferences = await storage.loadUiPreferences();
    advancedMode = uiPreferences['advancedMode'] == true;
    final legacyIdentity = await storage.loadOrCreateIdentity();
    final seedStore = Platform.isAndroid
        ? AndroidIdentitySeedStore()
        : FileIdentitySeedStore(root);
    final seeds = await seedStore.loadOrCreate();
    _identity = await LocalCryptoIdentity.fromSeeds(
      seeds: seeds,
      label: legacyIdentity.label,
    );
    ownMmId = _identity.mmId;
    ownDeviceLabel = _identity.label;
    ownFingerprint = _identity.fingerprint;
    ownIdentityPublicKey = _identity.identityPublicKeyB64;
    ownAgreementPublicKey = _identity.agreementPublicKeyB64;
    identitySeedStorage = _identity.seedStorage;
    await storage.savePublicIdentityMetadata(
      mmId: ownMmId,
      label: ownDeviceLabel,
      fingerprint: ownFingerprint,
      identityPublicKey: _identity.identityPublicKeyB64,
      agreementPublicKey: _identity.agreementPublicKeyB64,
      seedStorage: identitySeedStorage,
    );

    M07CryptoProvider? cryptoProvider;
    if (Platform.isAndroid && storageCrypto != null) {
      final engine = await AndroidM07DirectRatchetEngine.tryCreate();
      if (engine != null) {
        cryptoProvider = M07AtomicProvider(
          localMmId: ownMmId,
          engine: engine,
          store: M07ProviderStateStore(
            root: root,
            crypto: storageCrypto,
          ),
        );
      }
    }

    final transports = <MessageTransport>[];
    final lan = LanTransport(ownMmId: ownMmId, deviceLabel: ownDeviceLabel);
    _lan = lan;
    transports.add(lan);
    _lanSub = lan.events.listen(_onLanEvent);

    if (bridge != null && usbBridge != null) {
      final externalSession = MmUartExternalRadioSession();
      final externalRadio = MmUartMessageTransport(
        session: externalSession,
        resolveRecipientBinding: _resolveMmUartBinding,
      );
      _externalRadioSession = externalSession;
      _externalRadio = externalRadio;
      _radioHilBench = MmUartHilBench(externalSession);
      transports.add(externalRadio);
      _externalRadioSub = externalRadio.events.listen(_onMmUartTransportEvent);
      _externalSessionSub = externalSession.events.listen(
        _onMmUartSessionEvent,
      );

      final lr24 = TransparentUartRadioTransport(
        bridge: usbBridge,
        ownMmId: ownMmId,
        ownLabel: ownDeviceLabel,
      );
      _lr24 = lr24;
      transports.add(lr24);
      _lr24Sub = lr24.events.listen(_onLr24Event);

      final ep2 = Ep2UartTransport(
        bridge: usbBridge,
        resolvePeerNode: _resolveEp2Node,
      );
      _ep2 = ep2;
      transports.add(ep2);
      _ep2Sub = ep2.events.listen(_onEp2Event);
      await refreshEp2Devices();

      radioState = bridge.state;
      final meshtastic = MeshtasticTransport(
        isReady: () => bridge.connected,
        sendToRadio: bridge.sendToRadio,
        resolveNodeNum: _resolveNodeNum,
      );
      _meshtastic = meshtastic;
      transports.add(meshtastic);
      _androidSub = bridge.events.listen((event) {
        if (event is AndroidMeshtasticState) {
          radioState = event.state;
          radioError = event.error;
          _addRadioLog(
            'STATE ${event.state}${event.error == null ? '' : ' | ${event.error}'}',
          );
          notifyListeners();
        } else if (event is AndroidMeshtasticEnvelope) {
          _addRadioLog('FROM_RADIO ${event.bytes.length} B');
          meshtastic.ingestFromRadio(event.bytes);
        } else if (event is AndroidMeshtasticLog) {
          _addRadioLog(event.message, atMillis: event.atMillis);
          notifyListeners();
        }
      });
      _meshtasticSub = meshtastic.events.listen(_onMeshtasticEvent);
      await refreshRadioDiagnostics();
    }

    _core = MeshMessengerCore(
      ownMmId: ownMmId,
      storage: storage,
      transports: transports,
      cryptoProvider: cryptoProvider,
      requirePrivateE2ee: securityPolicy.requirePrivateE2ee,
    );
    await _core.restore();
    _deliverySub = _core.deliveryChanges.listen((_) {
      if (initialized) notifyListeners();
    });

    contacts = await _core.contacts();
    groups = await _core.groups();
    await _refreshMessageRequests();
    for (final receipt in await _core.groupReceipts()) {
      _groupReceipts
          .putIfAbsent(receipt.messageId, () => <String>{})
          .add(receipt.memberMmId);
    }
    lan.setAllowedPeers(
      contacts
          .where((contact) => contact.verified)
          .map((contact) => contact.mmId),
    );
    selectedPeerMmId = null;
    activeConversation = const ConversationRef.channel('general');
    await _reloadMessages();
    initialized = true;

    await refreshLanPermission();
    if (startRuntime) {
      if (lanPermissionGranted) {
        await startLan();
      } else {
        lanState = 'permission';
      }
      _maintenanceTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_runMaintenance()),
      );
    }
    notifyListeners();
  }

  Contact? get selectedContact {
    if (activeConversation.kind != ConversationKind.direct) return null;
    final id = selectedPeerMmId;
    if (id == null) return null;
    return contacts.where((c) => c.mmId == id).firstOrNull;
  }

  bool get isDirectChat => activeConversation.kind == ConversationKind.direct;
  bool get selectedDirectIsKnownContact => selectedContact != null;
  String get selectedDirectDisplayName {
    final id = selectedPeerMmId;
    return id == null ? '' : displayNameForMmId(id);
  }

  bool get isGeneralChat =>
      activeConversation.kind == ConversationKind.channel &&
      activeConversation.id == 'general';

  GroupDefinition? get selectedGroup {
    if (activeConversation.kind != ConversationKind.group) return null;
    return groups.where((g) => g.groupId == activeConversation.id).firstOrNull;
  }

  bool get isGroupChat => activeConversation.kind == ConversationKind.group;

  List<String> get nearbyPeerMmIds {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
    final hidden = <String>{
      ...contacts.map((c) => c.mmId),
      ...messageRequestPeerMmIds,
    };
    return _peerLastSeen.entries
        .where(
          (entry) =>
              entry.key != ownMmId &&
              entry.value.isAfter(cutoff) &&
              !hidden.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false)
      ..sort();
  }

  String groupDeliveryLabelFor(String messageId) {
    final group = selectedGroup;
    if (group == null) return 'Сохранено';
    final remoteCount = group.memberMmIds
        .where((mmId) => mmId != ownMmId)
        .length;
    if (remoteCount == 0) return 'Сохранено';
    final delivered = _groupReceipts[messageId]?.length ?? 0;
    final pending = _core.delivery
        .legsForMessage(messageId)
        .where((leg) => leg.isGroup && !leg.state.isTerminal)
        .length;
    if (delivered >= remoteCount) return 'Доставлено $delivered/$remoteCount';
    if (delivered > 0) return 'Доставлено $delivered/$remoteCount';
    if (pending > 0) return 'Ожидает $pending/$remoteCount';
    return 'Отправлено 0/$remoteCount';
  }

  int get generalOnlineCount {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
    return _peerLastSeen.values.where((seen) => seen.isAfter(cutoff)).length;
  }

  int channelReceiptCountFor(String messageId) =>
      _channelReceipts[messageId]?.length ?? 0;

  String displayNameForMmId(String mmId) {
    final contact = contacts.where((c) => c.mmId == mmId).firstOrNull;
    if (contact != null) return contact.displayName;
    final advertised = _peerLabels[mmId]?.trim();
    if (advertised != null && advertised.isNotEmpty) return advertised;
    final compact = mmId.length <= 12 ? mmId : mmId.substring(0, 12);
    return 'Узел $compact';
  }

  Set<String> capabilitiesForMmId(String mmId) =>
      Set.unmodifiable(_peerCapabilities[mmId] ?? const <String>{});

  void _markPeerSeen(String mmId) {
    if (mmId.isEmpty || mmId == ownMmId) return;
    _peerLastSeen[mmId] = DateTime.now().toUtc();
  }

  @visibleForTesting
  void injectNearbyPeerForTest(String mmId, {String label = 'Nearby Test'}) {
    final cleanId = mmId.trim();
    if (cleanId.isEmpty || cleanId == ownMmId) return;
    _peerLastSeen[cleanId] = DateTime.now().toUtc();
    _peerLabels[cleanId] = label;
    notifyListeners();
  }

  List<DeliveryEnvelope> get pendingDeliveries => _core.pending;
  DeliveryState? deliveryStateFor(String id) => _core.deliveryById(id)?.state;

  List<ConversationMessage> get mapMessages =>
      messages.where((message) => message.isMapPoint).toList(growable: false);

  void requestMapFocus(MapPoint point) {
    requestedMapFocus = point;
    mapFocusSerial++;
    notifyListeners();
  }

  Future<void> sendMapPoint({
    required double latitude,
    required double longitude,
    String label = '',
    String note = '',
  }) async {
    if (busy) return;
    final conversation = activeConversation;
    if (conversation.kind == ConversationKind.group) {
      throw StateError('GROUP_MAP_POINT_NOT_SUPPORTED');
    }
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Неверные координаты точки');
    }
    busy = true;
    notifyListeners();
    try {
      final now = DateTime.now().toUtc();
      final cleanLabel = label.trim();
      final cleanNote = note.trim();
      final point = MapPoint(
        id: 'p-${now.microsecondsSinceEpoch}',
        latitude: latitude,
        longitude: longitude,
        createdAt: now,
        label: cleanLabel.length > 64
            ? cleanLabel.substring(0, 64)
            : cleanLabel,
        note: cleanNote.length > 160 ? cleanNote.substring(0, 160) : cleanNote,
      );
      if (conversation.kind == ConversationKind.channel) {
        await _core.sendChannelMapPoint(
          channelId: conversation.id,
          point: point,
        );
      } else {
        await _core.sendMapPoint(peerMmId: conversation.id, point: point);
      }
      await _reloadMessages();
      requestMapFocus(point);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectGeneralChat() async {
    activeConversation = const ConversationRef.channel('general');
    selectedPeerMmId = null;
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> selectDirectPeer(String mmId) async {
    final clean = mmId.trim();
    if (clean.isEmpty || clean == ownMmId) return;
    activeConversation = ConversationRef.direct(clean);
    selectedPeerMmId = clean;
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> selectContact(String mmId) => selectDirectPeer(mmId);

  Future<void> selectGroup(String groupId) async {
    activeConversation = ConversationRef.group(groupId);
    selectedPeerMmId = null;
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> createGroup({
    required String displayName,
    required Iterable<String> memberMmIds,
  }) async {
    final group = await _core.createGroup(
      displayName: displayName,
      memberMmIds: memberMmIds,
    );
    groups = await _core.groups();
    final lr24 = _lr24;
    final peer = lr24PeerMmId;
    if (lr24?.isAvailable == true && peer != null && group.contains(peer)) {
      unawaited(lr24!.sendGroupDescriptor(descriptor: group, toMmId: peer));
    }
    activeConversation = ConversationRef.group(group.groupId);
    selectedPeerMmId = null;
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty || busy) return;
    busy = true;
    notifyListeners();
    try {
      if (activeConversation.kind == ConversationKind.channel) {
        await _core.sendChannelText(
          channelId: activeConversation.id,
          text: text,
        );
      } else if (activeConversation.kind == ConversationKind.group) {
        final group = selectedGroup;
        final peer = lr24PeerMmId;
        if (group != null &&
            peer != null &&
            group.contains(peer) &&
            _lr24?.isAvailable == true) {
          await _lr24!.sendGroupDescriptor(descriptor: group, toMmId: peer);
        }
        await _core.sendGroupText(groupId: activeConversation.id, text: text);
      } else {
        final peer = selectedPeerMmId;
        if (peer == null) return;
        await _core.sendText(peerMmId: peer, text: text);
      }
      await _reloadMessages();
      if (activeConversation.kind == ConversationKind.direct) {
        await _refreshMessageRequests();
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setAdvancedMode(bool value) async {
    if (advancedMode == value) return;
    advancedMode = value;
    notifyListeners();
    final storage = _appStorage;
    if (storage != null) {
      await storage.saveUiPreferences(<String, Object?>{
        'advancedMode': advancedMode,
      });
    }
  }

  Future<void> acknowledge(String messageId) async {
    final peer = selectedPeerMmId;
    if (peer == null) return;
    await _core.acknowledge(messageId, peer);
    notifyListeners();
  }

  Future<void> addContactCard(String raw, {String? displayNameOverride}) async {
    final card = ContactCard.parse(raw);
    final cleanId = card.mmId.trim();
    final existing = contacts
        .where((contact) => contact.mmId == cleanId)
        .firstOrNull;
    final overrideName = displayNameOverride?.trim();
    final cleanName = overrideName != null && overrideName.isNotEmpty
        ? overrideName
        : existing?.displayName.trim().isNotEmpty == true
        ? existing!.displayName.trim()
        : card.displayName.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw const FormatException('Invalid local contact name');
    }

    final incomingFingerprint = card.fingerprint?.trim() ?? '';
    final incomingIdentityKey = card.identityPublicKey?.trim() ?? '';
    final incomingAgreementKey = card.agreementPublicKey?.trim() ?? '';
    final identityChanged =
        existing != null &&
        ((incomingFingerprint.isNotEmpty &&
                (existing.fingerprint?.trim().isNotEmpty ?? false) &&
                incomingFingerprint != existing.fingerprint!.trim()) ||
            (incomingIdentityKey.isNotEmpty &&
                (existing.identityPublicKey?.trim().isNotEmpty ?? false) &&
                incomingIdentityKey != existing.identityPublicKey!.trim()) ||
            (incomingAgreementKey.isNotEmpty &&
                (existing.agreementPublicKey?.trim().isNotEmpty ?? false) &&
                incomingAgreementKey != existing.agreementPublicKey!.trim()));
    final preserveVerification = existing?.verified == true && !identityChanged;

    await _core.saveContact(
      Contact(
        mmId: cleanId,
        displayName: cleanName,
        verified: preserveVerification,
        fingerprint: incomingFingerprint.isEmpty
            ? existing?.fingerprint
            : incomingFingerprint,
        identityPublicKey: incomingIdentityKey.isEmpty
            ? existing?.identityPublicKey
            : incomingIdentityKey,
        agreementPublicKey: incomingAgreementKey.isEmpty
            ? existing?.agreementPublicKey
            : incomingAgreementKey,
        preKeyBundle: card.preKeyBundle?.trim().isNotEmpty == true
            ? card.preKeyBundle!.trim()
            : existing?.preKeyBundle,
        verifiedAt: preserveVerification ? existing?.verifiedAt : null,
        meshtasticNodeNum: card.meshtasticNodeId == null
            ? existing?.meshtasticNodeNum
            : _parseNodeNum(card.meshtasticNodeId),
        ep2NodeId: card.radioNodeId ?? existing?.ep2NodeId,
      ),
    );
    contacts = await _core.contacts();
    await _refreshMessageRequests();
    selectedPeerMmId = cleanId;
    activeConversation = ConversationRef.direct(cleanId);
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> prepareSmallFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    const maxUiFileBytes = 100 * 1024;
    if (bytes.isEmpty) {
      throw ArgumentError('Файл пустой');
    }
    if (bytes.length > maxUiFileBytes) {
      throw ArgumentError('Пока поддерживаются файлы до 100 КБ');
    }

    // Match the proven MM U1 LR24 transfer baseline: one 1024-byte
    // block at a time. The previous adaptive path treated missing LR24 RSSI as
    // an ideal link and selected 4096-byte bulk chunks, which is too aggressive
    // for 57 600 baud stop-and-wait ACK timing.
    const chunkSize = 1024;
    const transferProfile = AdaptiveLinkProfile.balanced;
    final transferId =
        'f-' + DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
    final plan = M05FileTransferCore.createPlan(
      transferId: transferId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      chunkSize: chunkSize,
    );

    preparedFileName = plan.manifest.fileName;
    preparedFileBytes = plan.manifest.totalBytes;
    preparedFileChunks = plan.manifest.chunkCount;
    preparedFileSha256 = plan.manifest.sha256Hex;
    preparedFileProfile = transferProfile;
    _preparedFilePlan = plan;
    fileTransferState = 'prepared';
    fileTransferAckedChunks = 0;
    fileTransferNotice =
        'Подготовлено: ' +
        plan.manifest.chunkCount.toString() +
        ' блоков по ' +
        chunkSize.toString() +
        ' Б · ' +
        transferProfile.name;
    notifyListeners();
  }

  Future<void> sendPreparedSmallFile() async {
    final plan = _preparedFilePlan;
    if (plan == null || fileTransferSending || busy) return;
    final lr24 = _lr24;
    if (lr24 == null || !lr24.isAvailable) {
      throw StateError('LR24 не подключён');
    }

    busy = true;
    fileTransferSending = true;
    fileTransferState = 'sendingManifest';
    fileTransferAckedChunks = 0;
    fileTransferNotice = 'Согласование передачи · ' + plan.manifest.fileName;
    notifyListeners();
    try {
      await lr24.sendFilePlan(plan);
      fileTransferState = 'completed';
      fileTransferAckedChunks = plan.manifest.chunkCount;
      fileTransferNotice =
          'Доставлено: ' +
          plan.manifest.fileName +
          ' · ' +
          plan.manifest.totalBytes.toString() +
          ' Б';
      _addLr24Log(
        'FILE SENT ' +
            plan.manifest.transferId +
            ' ' +
            plan.manifest.fileName +
            ' ' +
            plan.manifest.totalBytes.toString() +
            'B',
      );
      clearPreparedFile(notify: false, keepTransferStatus: true);
    } catch (error) {
      if (fileTransferState == 'cancelled') {
        fileTransferNotice = 'Передача отменена';
        _addLr24Log('FILE CANCELLED ' + plan.manifest.transferId);
        return;
      }
      fileTransferState = 'failed';
      fileTransferNotice = 'Ошибка передачи файла: ' + error.toString();
      _addLr24Log(
        'FILE SEND ERROR ' +
            plan.manifest.transferId +
            ' | ' +
            error.toString(),
      );
      rethrow;
    } finally {
      busy = false;
      fileTransferSending = false;
      notifyListeners();
    }
  }

  void pausePreparedFileTransfer() {
    final plan = _preparedFilePlan;
    final lr24 = _lr24;
    if (plan == null || lr24 == null || !fileTransferCanPause) return;
    if (!lr24.pauseFileTransfer(plan.manifest.transferId)) return;
    fileTransferState = 'pausedUser';
    fileTransferNotice =
        'Пауза · сохранено $fileTransferAckedChunks/${plan.manifest.chunkCount}';
    notifyListeners();
  }

  void continuePreparedFileTransfer() {
    final plan = _preparedFilePlan;
    final lr24 = _lr24;
    if (plan == null || lr24 == null || !fileTransferPausedByUser) return;
    if (!lr24.resumeFileTransfer(plan.manifest.transferId)) {
      fileTransferNotice = 'Сначала восстановите радиоканал';
      notifyListeners();
      return;
    }
    fileTransferState = 'sendingManifest';
    fileTransferNotice = 'Продолжаем передачу…';
    notifyListeners();
  }

  Future<void> cancelPreparedFileTransfer() async {
    final plan = _preparedFilePlan;
    final lr24 = _lr24;
    if (plan == null || lr24 == null || !fileTransferSending) return;
    final cancelled = await lr24.cancelFileTransfer(plan.manifest.transferId);
    if (!cancelled) return;
    fileTransferState = 'cancelled';
    fileTransferNotice = 'Передача отменена';
    notifyListeners();
  }

  void clearPreparedFile({
    bool notify = true,
    bool keepTransferStatus = false,
  }) {
    preparedFileName = null;
    preparedFileBytes = null;
    preparedFileChunks = null;
    preparedFileSha256 = null;
    _preparedFilePlan = null;
    if (!keepTransferStatus) {
      fileTransferState = 'idle';
      fileTransferAckedChunks = 0;
    }
    if (notify) {
      fileTransferNotice = null;
      notifyListeners();
    }
  }

  Future<void> addLocalContact({
    required String mmId,
    required String displayName,
    String? meshtasticNode,
    String? ep2Node,
  }) async {
    final cleanId = mmId.trim();
    final cleanName = displayName.trim();
    if (cleanId.isEmpty || cleanName.isEmpty) return;
    final nodeNum = _parseNodeNum(meshtasticNode);
    final ep2NodeId = _parseEp2Node(ep2Node);
    await _core.saveContact(
      Contact(
        mmId: cleanId,
        displayName: cleanName,
        meshtasticNodeNum: nodeNum,
        ep2NodeId: ep2NodeId,
      ),
    );
    contacts = await _core.contacts();
    await _refreshMessageRequests();
    _lan?.setAllowedPeers(
      contacts
          .where((contact) => contact.verified)
          .map((contact) => contact.mmId),
    );
    selectedPeerMmId = cleanId;
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> renameContact({
    required String mmId,
    required String displayName,
  }) async {
    final cleanId = mmId.trim();
    final cleanName = displayName.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw const FormatException('Invalid local contact name');
    }
    final existing = contacts
        .where((contact) => contact.mmId == cleanId)
        .firstOrNull;
    if (existing == null) throw StateError('CONTACT_NOT_FOUND');
    await _core.saveContact(
      Contact(
        mmId: existing.mmId,
        displayName: cleanName,
        verified: existing.verified,
        identityPublicKey: existing.identityPublicKey,
        agreementPublicKey: existing.agreementPublicKey,
        preKeyBundle: existing.preKeyBundle,
        fingerprint: existing.fingerprint,
        verifiedAt: existing.verifiedAt,
        meshtasticNodeNum: existing.meshtasticNodeNum,
        ep2NodeId: existing.ep2NodeId,
      ),
    );
    contacts = await _core.contacts();
    notifyListeners();
  }

  Future<void> addNearbyPeerAsContact(
    String mmId, {
    String? displayName,
  }) async {
    final cleanId = mmId.trim();
    if (cleanId.isEmpty || hasContact(cleanId)) return;
    final cleanName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : displayNameForMmId(cleanId);
    if (cleanName.isEmpty || cleanName.length > 80) {
      throw const FormatException('Invalid local contact name');
    }
    await _core.saveContact(Contact(mmId: cleanId, displayName: cleanName));
    contacts = await _core.contacts();
    await _refreshMessageRequests();
    selectedPeerMmId = cleanId;
    activeConversation = ConversationRef.direct(cleanId);
    await _reloadMessages();
    notifyListeners();
  }

  bool hasContact(String mmId) =>
      contacts.any((contact) => contact.mmId == mmId);

  Future<void> _refreshMessageRequests() async {
    final known = contacts.map((contact) => contact.mmId).toSet();
    final all = await _core.allMessages();
    final ids = <String>{};
    for (final message in all) {
      if (!message.effectiveConversationKey.startsWith('direct:')) continue;
      final id = message.peerMmId.trim();
      if (id.isEmpty || id == ownMmId || known.contains(id)) continue;
      ids.add(id);
    }
    messageRequestPeerMmIds = ids.toList(growable: false)..sort();
  }

  LanPairingSession? pairingFor(String mmId) => lanPairings[mmId];

  Future<void> addLanPeerAsContact(LanPeer peer) => startLanPairing(peer);

  Future<void> startLanPairing(LanPeer peer) async {
    final lan = _lan;
    if (lan == null || !lanReady) return;
    final pairingId = IdentityCrypto.randomPairingId();
    final placeholder = LanPairingSession(
      pairingId: pairingId,
      peerMmId: peer.mmId,
      peerLabel: peer.label,
      fingerprint: '',
      identityPublicKey: const [],
      agreementPublicKey: const [],
      sas: '',
      initiator: true,
    );
    lanPairings[peer.mmId] = placeholder;
    lanNotice = 'Запрос проверки отправлен на ${peer.label}';
    notifyListeners();
    try {
      final payload = await _identity.signedPairingPacket(
        kind: 'pair_offer',
        pairingId: pairingId,
        toMmId: peer.mmId,
      );
      await lan.sendPairing(
        mmId: peer.mmId,
        kind: 'pair_offer',
        payload: payload,
      );
      _addLanLog('PAIR OFFER $pairingId -> ${peer.mmId}');
    } catch (error) {
      lanPairings.remove(peer.mmId);
      lanNotice = 'Не удалось начать проверку ключей';
      _addLanLog('PAIR OFFER ERROR ${peer.mmId} | $error');
      notifyListeners();
    }
  }

  Future<void> confirmLanPairing(String mmId) async {
    final session = lanPairings[mmId];
    final lan = _lan;
    if (session == null || session.sas.isEmpty || lan == null) return;
    final updated = session.copyWith(localConfirmed: true);
    lanPairings[mmId] = updated;
    final payload = await _identity.signedPairingPacket(
      kind: 'pair_confirm',
      pairingId: session.pairingId,
      toMmId: mmId,
    );
    await lan.sendPairing(mmId: mmId, kind: 'pair_confirm', payload: payload);
    _addLanLog('PAIR CONFIRM ${session.pairingId} -> $mmId');
    if (updated.remoteConfirmed) {
      await _finalizeLanPairing(updated);
    } else {
      lanNotice = 'Код подтверждён здесь · ждём второй телефон';
      notifyListeners();
    }
  }

  Future<void> cancelLanPairing(String mmId) async {
    final session = lanPairings.remove(mmId);
    final lan = _lan;
    if (session != null && lan != null && lanReady) {
      try {
        final payload = await _identity.signedPairingPacket(
          kind: 'pair_cancel',
          pairingId: session.pairingId,
          toMmId: mmId,
        );
        await lan.sendPairing(
          mmId: mmId,
          kind: 'pair_cancel',
          payload: payload,
        );
      } catch (_) {}
    }
    lanNotice = 'Проверка ключей отменена';
    notifyListeners();
  }

  Future<void> _finalizeLanPairing(LanPairingSession session) async {
    final existing = contacts
        .where((contact) => contact.mmId == session.peerMmId)
        .firstOrNull;
    await _core.saveContact(
      Contact(
        mmId: session.peerMmId,
        displayName: existing?.displayName ?? session.peerLabel,
        verified: true,
        identityPublicKey: base64UrlEncode(session.identityPublicKey),
        agreementPublicKey: base64UrlEncode(session.agreementPublicKey),
        preKeyBundle: existing?.preKeyBundle,
        fingerprint: session.fingerprint,
        verifiedAt: DateTime.now().toUtc(),
        meshtasticNodeNum: existing?.meshtasticNodeNum,
        ep2NodeId: existing?.ep2NodeId,
      ),
    );
    contacts = await _core.contacts();
    _lan?.setAllowedPeers(
      contacts
          .where((contact) => contact.verified)
          .map((contact) => contact.mmId),
    );
    lanPairings.remove(session.peerMmId);
    selectedPeerMmId = session.peerMmId;
    await _reloadMessages();
    lanNotice = '${session.peerLabel} · ключи проверены · контакт доверенный';
    _addLanLog('PAIR VERIFIED ${session.peerMmId} ${session.fingerprint}');
    notifyListeners();
  }

  Future<void> refreshLanPermission() async {
    final bridge = _localNetworkBridge;
    if (bridge == null) {
      lanPermission = const {'required': false, 'granted': true, 'missing': []};
      return;
    }
    try {
      lanPermission = await bridge.permissionStatus();
      if (lanPermissionGranted && lanState == 'permission')
        lanState = 'offline';
    } catch (error) {
      lanError = '$error';
      _addLanLog('PERMISSION STATUS ERROR $error');
    }
    if (initialized) notifyListeners();
  }

  Future<void> requestLanPermission() async {
    final bridge = _localNetworkBridge;
    if (bridge == null) {
      lanPermission = const {'required': false, 'granted': true, 'missing': []};
      await startLan();
      return;
    }
    try {
      lanPermission = await bridge.requestPermission();
      if (lanPermissionGranted) {
        lanError = null;
        await startLan();
      } else {
        lanState = 'permission';
        lanError = 'Нет разрешения на локальную сеть';
      }
    } catch (error) {
      lanError = '$error';
      _addLanLog('PERMISSION ERROR $error');
    }
    notifyListeners();
  }

  Future<void> startLan() async {
    final lan = _lan;
    if (lan == null) return;
    if (!lanPermissionGranted) {
      lanState = 'permission';
      notifyListeners();
      return;
    }
    try {
      lanError = null;
      await lan.start();
      lanState = lan.state;
      lanLocalAddresses = lan.localAddresses;
    } catch (error) {
      lanState = 'error';
      lanError = '$error';
      _addLanLog('START ERROR $error');
    }
    notifyListeners();
  }

  Future<void> restartLan() async {
    final lan = _lan;
    if (lan == null || !lanPermissionGranted || busy) return;
    busy = true;
    notifyListeners();
    try {
      lanError = null;
      await lan.restart();
      lanLocalAddresses = lan.localAddresses;
    } catch (error) {
      lanState = 'error';
      lanError = '$error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> announceLan() async {
    final lan = _lan;
    if (lan == null || !lanReady) return;
    await lan.announce();
    lanNotice = 'Поиск устройств отправлен в локальную сеть';
    notifyListeners();
  }

  Future<void> probeLanPeer(String mmId) async {
    final lan = _lan;
    if (lan == null || !lanReady || lanProbePending.contains(mmId)) return;
    lanProbePending.add(mmId);
    lanRttMs.remove(mmId);
    notifyListeners();
    try {
      await lan.probe(mmId);
    } catch (error) {
      lanProbePending.remove(mmId);
      lanError = '$error';
      _addLanLog('PING ERROR $mmId | $error');
      notifyListeners();
    }
  }

  void clearLanLog() {
    lanLog.clear();
    notifyListeners();
  }

  void _addLanLog(String message) {
    if (message.trim().isEmpty) return;
    final time = DateTime.now();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    lanLog.add('$stamp · $message');
    if (lanLog.length > 100) {
      lanLog.removeRange(0, lanLog.length - 100);
    }
  }

  Future<void> _runMaintenance() async {
    if (_maintenanceBusy) return;
    _maintenanceBusy = true;
    try {
      await _core.maintenance();
      final lr24 = _lr24;
      if (lr24?.isAvailable == true) {
        _lr24DiscoveryTick++;
        final noFreshPeer = !lr24!.hasFreshPeers;
        final due = noFreshPeer
            ? _lr24DiscoveryTick >= 3
            : _lr24DiscoveryTick >= 15;
        if (due) {
          _lr24DiscoveryTick = 0;
          try {
            await lr24.discoverPeers();
            _addLr24Log(
              noFreshPeer
                  ? 'DISCOVERY refresh · peer not confirmed'
                  : 'DISCOVERY refresh · keepalive',
            );
          } catch (error) {
            _addLr24Log('DISCOVERY ERROR $error');
          }
        }
      } else {
        _lr24DiscoveryTick = 0;
      }
      _usbMaintenanceTick++;
      if (_usbMaintenanceTick >= 3) {
        _usbMaintenanceTick = 0;
        await _runUsbMaintenance();
      }
    } finally {
      _maintenanceBusy = false;
    }
  }

  Future<void> _runUsbMaintenance() async {
    final bridge = _usbBridge;
    if (bridge == null || _usbMaintenanceBusy || busy) return;
    _usbMaintenanceBusy = true;
    try {
      final devices = await bridge.devices();
      final ids = devices.map((device) => device.deviceId).toSet();
      final changed =
          devices.length != ep2Devices.length ||
          devices.any(
            (device) => !ep2Devices.any(
              (old) =>
                  old.deviceId == device.deviceId &&
                  old.permission == device.permission &&
                  old.driver == device.driver,
            ),
          );
      if (changed) {
        ep2Devices = devices;
        _addEp2Log('USB devices=${devices.length}');
      }

      final lr24Id = lr24ConnectedDeviceId;
      if (lr24Id != null && !ids.contains(lr24Id)) {
        _addLr24Log('USB device=$lr24Id detached');
        lr24ConnectedDeviceId = null;
        _lr24Active = false;
        try {
          await _lr24?.disconnect();
        } catch (_) {}
        lr24State = 'disconnected';
        lr24Error = null;
      }

      final connectedId = ep2ConnectedDeviceId;
      if (connectedId != null && !ids.contains(connectedId)) {
        _addEp2Log('USB device=$connectedId detached');
        ep2ConnectedDeviceId = null;
        _mmUartActive = false;
        try {
          await _externalRadioSession?.disconnect();
        } catch (_) {}
        try {
          await _ep2?.disconnect();
        } catch (_) {}
        ep2State = 'disconnected';
        ep2Protocol = 'unknown';
        ep2DetectedProtocol = 'unknown';
        ep2InfoNotice = 'Радиомодуль отключён. Ждём повторного подключения.';
      }

      if (!ep2Connected && !lr24Connected && devices.length == 1 && changed) {
        final device = devices.single;
        final saved = _usbProfileBinding;
        if (saved != null &&
            saved.profileId == 'MICOAIR_LR24_F_STOCK' &&
            saved.matches(
              vendorId: device.vendorId,
              productId: device.productId,
              driver: device.driver,
              deviceName: device.name,
            )) {
          ep2InfoNotice =
              'Сохранённый профиль LR24-F найден · переподключаем без probe.';
          _addEp2Log(
            'USB device=${device.deviceId} saved LR24 binding matched; no active probe',
          );
          await connectLr24(device.deviceId, rememberProfile: false);
        } else {
          ep2InfoNotice =
              'USB-модуль найден · выбери LR24-F или Авто M03. '
              'Активный probe не запускается до выбора профиля.';
          _addEp2Log(
            'USB device=${device.deviceId} waiting profile selection; no active probe',
          );
        }
      }

      if (changed && initialized) notifyListeners();
    } catch (error) {
      _addEp2Log('USB WATCH ERROR $error');
    } finally {
      _usbMaintenanceBusy = false;
    }
  }

  Future<void> _onLanEvent(LanTransportEvent event) async {
    if (event is LanStateEvent) {
      lanState = event.state;
      lanError = event.error;
      lanLocalAddresses = _lan?.localAddresses ?? const [];
      _addLanLog(
        'STATE ${event.state}${event.error == null ? '' : ' | ${event.error}'}',
      );
      notifyListeners();
      return;
    }
    if (event is LanPeersEvent) {
      lanPeers = event.peers;
      notifyListeners();
      return;
    }
    if (event is LanLogEvent) {
      _addLanLog(event.message);
      notifyListeners();
      return;
    }
    if (event is LanDeliveryEvent) {
      await _core.recipientDeliveryResult(
        messageId: event.messageId,
        fromMmId: event.recipientMmId,
        ok: event.ok,
        detail: event.detail,
      );
      _addLanLog(
        '${event.ok ? 'ACK' : 'NAK'} ${event.messageId}${event.detail == null ? '' : ' | ${event.detail}'}',
      );
      notifyListeners();
      return;
    }
    if (event is LanProbeEvent) {
      lanProbePending.remove(event.mmId);
      if (event.ok && event.rttMillis != null) {
        lanRttMs[event.mmId] = event.rttMillis!;
        lanNotice = 'Связь с устройством проверена · ${event.rttMillis} мс';
      } else {
        lanRttMs.remove(event.mmId);
        lanNotice = 'Устройство не ответило на проверку связи';
      }
      notifyListeners();
      return;
    }
    if (event is LanPairingEvent) {
      await _handleLanPairingEvent(event);
      return;
    }
    if (event is LanUntrustedTextEvent) {
      final peer = lanPeers.where((p) => p.mmId == event.fromMmId).firstOrNull;
      lanNotice =
          'Сообщение от ${peer?.label ?? event.fromMmId} отклонено: сначала добавьте контакт';
      _addLanLog('BLOCK UNKNOWN ${event.messageId} <- ${event.fromMmId}');
      notifyListeners();
      return;
    }
    if (event is LanIncomingText) {
      final contact = contacts
          .where((c) => c.mmId == event.fromMmId)
          .firstOrNull;
      if (contact == null) {
        _addLanLog('DROP UNKNOWN ${event.messageId} <- ${event.fromMmId}');
        return;
      }
      try {
        await _core.receiveText(
          messageId: event.messageId,
          fromMmId: event.fromMmId,
          text: event.text,
        );
        _lan?.acknowledgeIncoming(
          sourceAddress: event.sourceAddress,
          messageId: event.messageId,
          toMmId: event.fromMmId,
        );
      } catch (error) {
        _addLanLog('STORE ERROR ${event.messageId} | $error');
        return;
      }
      if (selectedPeerMmId == event.fromMmId) await _reloadMessages();
      lanNotice = 'Получено по LAN от ${contact.displayName}';
      notifyListeners();
      return;
    }
    if (event is LanIncomingData) {
      final contact = contacts
          .where((c) => c.mmId == event.fromMmId)
          .firstOrNull;
      if (contact == null) {
        _addLanLog('DROP UNKNOWN DATA ${event.messageId} <- ${event.fromMmId}');
        return;
      }
      if (event.messageClass != 'map_point' &&
          event.messageClass != m07DirectEnvelopeClass) {
        _addLanLog('DROP CLASS ${event.messageClass} ${event.messageId}');
        return;
      }
      try {
        if (event.messageClass == m07DirectEnvelopeClass) {
          await _core.receiveEncryptedDirect(
            messageId: event.messageId,
            fromMmId: event.fromMmId,
            encodedEnvelope: event.payload,
          );
        } else {
          await _core.receiveMapPoint(
            messageId: event.messageId,
            fromMmId: event.fromMmId,
            payload: event.payload,
          );
        }
        _lan?.acknowledgeIncoming(
          sourceAddress: event.sourceAddress,
          messageId: event.messageId,
          toMmId: event.fromMmId,
        );
      } catch (error) {
        _addLanLog('MAP STORE ERROR ${event.messageId} | $error');
        return;
      }
      if (selectedPeerMmId == event.fromMmId) await _reloadMessages();
      lanNotice = 'Получена точка от ${contact.displayName}';
      notifyListeners();
      return;
    }
  }

  Future<void> _handleLanPairingEvent(LanPairingEvent event) async {
    final lan = _lan;
    if (lan == null) return;
    try {
      final packet = await IdentityCrypto.verifyPairingPacket(
        event.payload,
        expectedKind: event.kind,
        expectedFromMmId: event.fromMmId,
        expectedToMmId: ownMmId,
      );
      if (event.kind == 'pair_offer') {
        final sas = await _identity.deriveSas(
          pairingId: packet.pairingId,
          remoteMmId: packet.fromMmId,
          remoteAgreementPublicKey: packet.agreementPublicKey,
        );
        lanPairings[packet.fromMmId] = LanPairingSession(
          pairingId: packet.pairingId,
          peerMmId: packet.fromMmId,
          peerLabel: packet.label,
          fingerprint: packet.fingerprint,
          identityPublicKey: packet.identityPublicKey,
          agreementPublicKey: packet.agreementPublicKey,
          sas: sas,
          initiator: false,
        );
        final answer = await _identity.signedPairingPacket(
          kind: 'pair_answer',
          pairingId: packet.pairingId,
          toMmId: packet.fromMmId,
        );
        await lan.sendPairing(
          mmId: packet.fromMmId,
          kind: 'pair_answer',
          payload: answer,
        );
        lanNotice = 'Запрос проверки от ${packet.label} · сравните код';
        _addLanLog(
          'PAIR OFFER VERIFIED ${packet.pairingId} <- ${packet.fromMmId}',
        );
        notifyListeners();
        return;
      }
      final session = lanPairings[packet.fromMmId];
      if (session == null || session.pairingId != packet.pairingId) {
        _addLanLog('PAIR DROP ${event.kind} ${packet.pairingId}');
        return;
      }
      if (event.kind == 'pair_answer') {
        final sas = await _identity.deriveSas(
          pairingId: packet.pairingId,
          remoteMmId: packet.fromMmId,
          remoteAgreementPublicKey: packet.agreementPublicKey,
        );
        lanPairings[packet.fromMmId] = LanPairingSession(
          pairingId: packet.pairingId,
          peerMmId: packet.fromMmId,
          peerLabel: packet.label,
          fingerprint: packet.fingerprint,
          identityPublicKey: packet.identityPublicKey,
          agreementPublicKey: packet.agreementPublicKey,
          sas: sas,
          initiator: true,
          localConfirmed: session.localConfirmed,
          remoteConfirmed: session.remoteConfirmed,
        );
        lanNotice = 'Ключи получены · сравните код на обоих телефонах';
        _addLanLog(
          'PAIR ANSWER VERIFIED ${packet.pairingId} <- ${packet.fromMmId}',
        );
        notifyListeners();
        return;
      }
      var current = session;
      if (current.identityPublicKey.isEmpty && event.kind == 'pair_confirm') {
        final sas = await _identity.deriveSas(
          pairingId: packet.pairingId,
          remoteMmId: packet.fromMmId,
          remoteAgreementPublicKey: packet.agreementPublicKey,
        );
        current = LanPairingSession(
          pairingId: packet.pairingId,
          peerMmId: packet.fromMmId,
          peerLabel: packet.label,
          fingerprint: packet.fingerprint,
          identityPublicKey: packet.identityPublicKey,
          agreementPublicKey: packet.agreementPublicKey,
          sas: sas,
          initiator: true,
          localConfirmed: session.localConfirmed,
          remoteConfirmed: session.remoteConfirmed,
        );
        lanPairings[packet.fromMmId] = current;
      }
      final sameKeys =
          base64UrlEncode(current.identityPublicKey) ==
              base64UrlEncode(packet.identityPublicKey) &&
          base64UrlEncode(current.agreementPublicKey) ==
              base64UrlEncode(packet.agreementPublicKey);
      if (!sameKeys) throw const FormatException('PAIRING_KEY_CHANGED');
      if (event.kind == 'pair_confirm') {
        final updated = current.copyWith(remoteConfirmed: true);
        lanPairings[packet.fromMmId] = updated;
        _addLanLog(
          'PAIR REMOTE CONFIRM ${packet.pairingId} <- ${packet.fromMmId}',
        );
        if (updated.localConfirmed) {
          await _finalizeLanPairing(updated);
        } else {
          lanNotice =
              '${packet.label} подтвердил код · подтвердите на этом телефоне';
          notifyListeners();
        }
        return;
      }
      if (event.kind == 'pair_cancel') {
        lanPairings.remove(packet.fromMmId);
        lanNotice = '${packet.label} отменил проверку ключей';
        _addLanLog('PAIR CANCEL ${packet.pairingId} <- ${packet.fromMmId}');
        notifyListeners();
      }
    } catch (error) {
      lanNotice = 'Проверка ключей отклонена';
      _addLanLog('PAIR REJECT ${event.kind} <- ${event.fromMmId} | $error');
      notifyListeners();
    }
  }

  Map<String, dynamic> buildDiagnosticSnapshot() {
    final lr24 = _lr24;
    final peer = lr24PeerMmId;
    return DiagnosticSnapshot.build(
      appVersion: MeshAppBuildInfo.display,
      ownMmId: ownMmId,
      activeConversation: activeConversation.key,
      transport: <String, dynamic>{
        'lanState': lanState,
        'meshtasticState': radioState,
        'ep2State': ep2State,
        'lr24State': lr24State,
        'lr24UsbReady': lr24Connected,
        'lr24PeerReachable': lr24PeerReachable,
        'lr24PeerMmId': peer,
        'lr24PeerAgeMs': peer == null ? null : lr24?.peerAgeMs(peer),
        'lr24FreshPeers':
            lr24?.freshPeerMmIds.toList(growable: false) ?? const <String>[],
        'lr24Baud': lr24Baud,
        'externalRadioFamily': externalRadioFamily,
        'externalBoardId': externalBoardId,
        'externalRadioSupportsMmrp': externalRadioSupportsMmrp,
      },
      counters: <String, dynamic>{
        'lr24TxBytes': lr24TxBytes,
        'lr24RxBytes': lr24RxBytes,
        'lr24TxFrames': lr24TxFrames,
        'lr24RxFrames': lr24RxFrames,
        'lr24BadFrames': lr24BadFrames,
        'lr24RttMs': lr24RttMs,
        'lr24QosControl': lr24?.qosPendingControl ?? 0,
        'lr24QosText': lr24?.qosPendingText ?? 0,
        'lr24QosFile': lr24?.qosPendingFile ?? 0,
        'pendingDeliveries': pendingDeliveries.length,
        'ep2TxCount': ep2TxCount,
        'ep2RxCount': ep2RxCount,
        'ep2LossCount': ep2LossCount,
        'ep2RetryCount': ep2RetryCount,
        'generalOnlineCount': generalOnlineCount,
      },
      extra: <String, dynamic>{
        'selectedUsbProfile':
            _usbProfileBinding?.toJson() ?? const <String, dynamic>{},
        'radioDiagnostics': radioDiagnostics,
        'lastRadioNotice': lastRadioNotice,
        'radioError': radioError,
        'ep2Error': ep2Error,
        'lr24Error': lr24Error,
        'fileTransfer': <String, dynamic>{
          'state': fileTransferState,
          'ackedChunks': fileTransferAckedChunks,
          'totalChunks': preparedFileChunks,
          'notice': fileTransferNotice,
          'lastReceivedFileName': lastReceivedFileName,
        },
        'outbox': pendingDeliveries
            .map(
              (item) => <String, dynamic>{
                'messageId': item.messageId,
                'deliveryId': item.effectiveDeliveryId,
                'recipient': item.recipientMmId,
                'state': item.state.name,
                'attempts': item.attempts,
                'transport': item.selectedTransportId,
                'lastError': item.lastError,
                'nextRetryAt': item.nextRetryAt?.toIso8601String(),
              },
            )
            .toList(growable: false),
        'lr24Log': List<String>.unmodifiable(lr24Log),
      },
    );
  }

  String diagnosticSnapshotJson() =>
      DiagnosticSnapshot.encode(buildDiagnosticSnapshot());

  Future<String?> exportDiagnosticSnapshot() async {
    final text = diagnosticSnapshotJson();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final fileName = 'Mesh Messenger diagnostics $stamp.txt';
    final bridge = _diagnosticsExportBridge;
    if (bridge != null) {
      return bridge.exportText(fileName: fileName, text: text);
    }
    final storage = _appStorage;
    if (storage == null) return null;
    final directory = Directory('${storage.root.path}/diagnostics');
    await directory.create(recursive: true);
    final output = File('${directory.path}/$fileName');
    await output.writeAsString(text, flush: true);
    return output.path;
  }

  Future<void> refreshRadioDiagnostics() async {
    final bridge = _androidBridge;
    if (bridge == null) return;
    try {
      radioPermissions = await bridge.permissionStatus();
      radioDiagnostics = await bridge.diagnostics();
    } catch (error) {
      radioError = '$error';
      _addRadioLog('DIAG ERROR $error');
    }
    notifyListeners();
  }

  void clearRadioLog() {
    radioLog.clear();
    notifyListeners();
  }

  void _addRadioLog(String message, {int? atMillis}) {
    if (message.trim().isEmpty) return;
    final time = atMillis != null && atMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(atMillis).toLocal()
        : DateTime.now();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    radioLog.add('$stamp · $message');
    if (radioLog.length > 100) {
      radioLog.removeRange(0, radioLog.length - 100);
    }
  }

  Future<void> requestRadioPermissions() async {
    final bridge = _androidBridge;
    if (bridge == null) return;
    final result = await bridge.requestPermissions();
    radioPermissions = result;
    final granted = result['granted'] == true;
    radioError = granted ? null : 'Нет разрешений Bluetooth';
    _addRadioLog(
      granted
          ? 'Bluetooth permissions granted'
          : 'Bluetooth permissions missing',
    );
    await refreshRadioDiagnostics();
  }

  Future<void> scanMeshtastic() async {
    final bridge = _androidBridge;
    if (bridge == null || busy) return;
    busy = true;
    radioError = null;
    notifyListeners();
    try {
      final permissions = await bridge.permissionStatus();
      if (permissions['granted'] != true) {
        await requestRadioPermissions();
      }
      _addRadioLog('SCAN requested');
      radioDevices = await bridge.scan();
      _addRadioLog('SCAN result ${radioDevices.length} device(s)');
      lastRadioNotice = radioDevices.isEmpty
          ? 'Meshtastic BLE устройства не найдены'
          : 'Найдено устройств: ${radioDevices.length}';
    } catch (error) {
      radioError = '$error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> connectMeshtastic(String deviceId) async {
    final bridge = _androidBridge;
    if (bridge == null || busy) return;
    busy = true;
    radioError = null;
    notifyListeners();
    try {
      _addRadioLog('CONNECT $deviceId');
      await bridge.connect(deviceId);
      await refreshRadioDiagnostics();
    } catch (error) {
      radioError = '$error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectMeshtastic() async {
    final bridge = _androidBridge;
    if (bridge == null) return;
    _addRadioLog('DISCONNECT requested');
    await bridge.disconnect();
    await refreshRadioDiagnostics();
  }

  Future<void> refreshEp2Devices() async {
    final bridge = _usbBridge;
    if (bridge == null) return;
    try {
      ep2Devices = await bridge.devices();
      for (final device in ep2Devices) {
        _addEp2Log(
          'USB id=${device.deviceId} vid=${device.vendorId.toRadixString(16).padLeft(4, '0')} pid=${device.productId.toRadixString(16).padLeft(4, '0')} driver=${device.driver} permission=${device.permission}',
        );
      }
      final status = await bridge.status();
      final state = status['state'] as String?;
      if (state != null && state.isNotEmpty && ep2State == 'unavailable') {
        ep2State = state;
      }
      ep2Error = status['error'] as String?;
    } catch (error) {
      ep2Error = '$error';
      _addEp2Log('USB LIST ERROR $error');
    }
    notifyListeners();
  }

  Future<void> connectLr24(int deviceId, {bool rememberProfile = true}) async {
    final lr24 = _lr24;
    if (lr24 == null || busy) return;
    busy = true;
    lr24Error = null;
    lr24ConnectedDeviceId = deviceId;
    lr24State = 'connecting';
    lr24RttMs = null;
    lr24PeerMmId = null;

    // LR24 is a separate transparent transport. Clear stale M03/EP2 probe
    // state so an earlier timeout cannot leak into the active LR24 UI.
    ep2Error = null;
    ep2State = 'offline';
    ep2DetectedProtocol = 'unknown';
    ep2Protocol = 'unknown';
    ep2Baud = null;
    ep2InfoNotice = null;
    ep2PingResult = null;
    ep2Rssi10 = null;
    ep2Snr10 = null;
    ep2RttMs = null;
    ep2TxCount = null;
    ep2RxCount = null;
    ep2LossCount = null;
    ep2RetryCount = null;
    ep2OtaNotice = null;
    ep2OtaSsid = null;
    ep2OtaPassword = null;
    ep2OtaUrl = null;
    notifyListeners();
    try {
      if (_mmUartActive) {
        await _externalRadioSession?.disconnect();
        _mmUartActive = false;
      }
      if (_ep2?.isAvailable == true) {
        await _ep2?.disconnect();
      }
      _lr24Active = true;
      _addLr24Log('CONNECT device=$deviceId baud=$lr24Baud');
      await lr24.connect(deviceId, baudRate: lr24Baud);
      if (rememberProfile) {
        final device = ep2Devices
            .where((item) => item.deviceId == deviceId)
            .firstOrNull;
        if (device != null) {
          final binding = UsbProfileBinding(
            profileId: 'MICOAIR_LR24_F_STOCK',
            vendorId: device.vendorId,
            productId: device.productId,
            driver: device.driver,
            deviceName: device.name,
          );
          await _usbProfileBindingStore?.save(binding);
          _usbProfileBinding = binding;
          _addLr24Log('PROFILE binding saved for ${device.name}');
        }
      }
    } catch (error) {
      _lr24Active = false;
      lr24Error = error.toString();
      lr24State = 'error';
      _addLr24Log('CONNECT ERROR $error');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectLr24() async {
    final lr24 = _lr24;
    if (lr24 == null) return;
    _addLr24Log('DISCONNECT requested');
    _lr24Active = false;
    lr24ConnectedDeviceId = null;
    lr24RttMs = null;
    lr24PeerMmId = null;
    try {
      await lr24.disconnect();
    } catch (error) {
      lr24Error = error.toString();
    }
    lr24State = 'disconnected';
    notifyListeners();
  }

  Future<void> probeLr24Peer() async {
    final lr24 = _lr24;
    if (lr24 == null || !lr24.isAvailable) return;
    lr24RttMs = null;
    lr24PeerMmId = null;
    lr24Error = null;
    notifyListeners();

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        // Link diagnostics must prove the transparent radio path independently
        // of a possibly stale contact/MM-ID binding.
        final elapsed = await lr24.probe(
          '*',
          timeout: const Duration(seconds: 2),
        );
        lr24RttMs = elapsed.inMilliseconds;
        _addLr24Log(
          'LINK PROBE broadcast attempt=$attempt RTT=${elapsed.inMilliseconds}ms',
        );
        notifyListeners();
        return;
      } catch (error) {
        lastError = error;
        _addLr24Log('LINK PROBE attempt=$attempt ERROR $error');
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }

    _addLr24Log('LINK PROBE FAILED | ${lastError ?? 'unknown'}');
    lr24Error = 'Второе устройство не ответило. USB подключён, радиоканал не подтверждён.';
    notifyListeners();
  }

  void clearLr24Log() {
    lr24Log.clear();
    notifyListeners();
  }

  void _addLr24Log(String message) {
    if (message.trim().isEmpty) return;
    final time = DateTime.now();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    lr24Log.add('$stamp | $message');
    if (lr24Log.length > 100) {
      lr24Log.removeRange(0, lr24Log.length - 100);
    }
  }

  Future<void> connectEp2(int deviceId) async {
    final ep2 = _ep2;
    final session = _externalRadioSession;
    final bridge = _usbBridge;
    if (ep2 == null || session == null || bridge == null || busy) return;
    busy = true;
    final selectedDevice = ep2Devices
        .where((item) => item.deviceId == deviceId)
        .firstOrNull;
    final saved = _usbProfileBinding;
    if (selectedDevice != null &&
        saved != null &&
        saved.profileId == 'MICOAIR_LR24_F_STOCK' &&
        saved.matches(
          vendorId: selectedDevice.vendorId,
          productId: selectedDevice.productId,
          driver: selectedDevice.driver,
          deviceName: selectedDevice.name,
        )) {
      await _usbProfileBindingStore?.clear();
      _usbProfileBinding = null;
      _addEp2Log('Saved LR24 binding cleared by manual Auto M03 selection');
    }
    if (lr24Connected || _lr24Active) {
      await disconnectLr24();
    }
    ep2Error = null;
    ep2DetectedProtocol = 'detecting';
    ep2RxBytes = 0;
    ep2TxBytes = 0;
    ep2LastHex = '';
    ep2Protocol = 'unknown';
    ep2Baud = null;
    ep2PingResult = null;
    ep2LocalNode = null;
    ep2Firmware = null;
    ep2Profile = null;
    ep2Rssi10 = null;
    ep2Snr10 = null;
    ep2RttMs = null;
    ep2TxCount = null;
    ep2RxCount = null;
    ep2LossCount = null;
    ep2RetryCount = null;
    ep2OtaSsid = null;
    ep2OtaPassword = null;
    ep2OtaUrl = null;
    ep2OtaNotice = null;
    ep2InfoNotice = null;
    notifyListeners();
    try {
      ep2ConnectedDeviceId = deviceId;
      _addEp2Log('AUTO USB device=$deviceId · MM-UART/1 first');
      if (_mmUartActive) {
        await session.disconnect();
        _mmUartActive = false;
      }
      if (ep2.isAvailable) {
        await ep2.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final link = AndroidUsbMmUartHostLink(
        bridge: bridge,
        deviceId: deviceId,
        baudRate: 115200,
      );
      try {
        final snapshot = await session.connect(link);
        if (!session.supportsMmrp) {
          throw StateError('MMRP/1_NOT_ADVERTISED');
        }
        _mmUartActive = true;
        ep2DetectedProtocol = 'mm-uart';
        ep2Protocol = 'MM-UART/1';
        ep2Baud = 115200;
        ep2Firmware = snapshot.info?.firmwareVersion;
        ep2Profile = snapshot.capabilities?.profileIds.firstOrNull;
        ep2InfoNotice = 'MM-UART/1 · MMRP/1 готов';
        _addEp2Log(
          'MM-UART READY fw=${ep2Firmware ?? '-'} radio=${snapshot.info?.radioFamily ?? '-'}',
        );
        try {
          final selftest = await session.compatSelftest();
          final passed = selftest['result'] == 'PASS' || selftest['ok'] == true;
          final nodeRaw = selftest['nodeBinding'] ?? selftest['nodeId'];
          final node = nodeRaw is num
              ? nodeRaw.toInt()
              : int.tryParse('$nodeRaw');
          if (node != null && node > 0) ep2LocalNode = node;
          if (passed) ep2InfoNotice = 'MM-UART/1 · MMRP/1 · самопроверка PASS';
          _addEp2Log('AUTO SELFTEST $selftest');
        } catch (error) {
          _addEp2Log('AUTO SELFTEST skipped | $error');
        }
        try {
          _applyMmUartStats(await session.refreshStats());
        } catch (error) {
          _addEp2Log('AUTO STATS skipped | $error');
        }
        return;
      } catch (error) {
        _mmUartActive = false;
        _addEp2Log('MM-UART fallback · $error');
        try {
          await session.disconnect();
        } catch (_) {}
      }

      _addEp2Log('AUTO fallback -> EP2 LINK / CRSF');
      await ep2.connectAuto(deviceId);
    } catch (error) {
      ep2Error = '$error';
      _addEp2Log('CONNECT ERROR $error');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectEp2() async {
    final ep2 = _ep2;
    final session = _externalRadioSession;
    if (ep2 == null) return;
    _addEp2Log('DISCONNECT requested');
    ep2ConnectedDeviceId = null;
    _mmUartActive = false;
    if (session != null) {
      try {
        await session.disconnect();
      } catch (_) {}
    }
    await ep2.disconnect();
    await refreshEp2Devices();
  }

  Future<void> refreshEp2Info() async {
    final ep2 = _ep2;
    if (ep2 == null || !ep2Connected) return;
    ep2Error = null;
    ep2InfoNotice = 'Запрашиваем INFO / STATS…';
    _addEp2Log('INFO / STATS requested');
    notifyListeners();
    try {
      if (_mmUartActive) {
        final session = _externalRadioSession;
        if (session == null) throw StateError('MM_UART_SESSION_MISSING');
        await session.refreshInfoAndCapabilities();
        final stats = await session.refreshStats();
        _applyMmUartStats(stats);
        ep2InfoNotice = 'MM-UART INFO / STATS обновлены';
      } else {
        await ep2.requestInfo();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await ep2.requestStats();
      }
    } catch (error) {
      ep2Error = '$error';
      _addEp2Log('INFO / STATS ERROR $error');
    }
    notifyListeners();
  }

  Future<void> runRadioSelfTest() async {
    if (!ep2Connected) return;
    ep2Error = null;
    ep2InfoNotice = 'Проверяем радиомодуль…';
    notifyListeners();
    try {
      if (_mmUartActive) {
        final session = _externalRadioSession;
        if (session == null) throw StateError('MM_UART_SESSION_MISSING');
        final result = await session.compatSelftest();
        final ok = result['ok'] != false;
        ep2InfoNotice = ok
            ? 'Самопроверка MM-UART пройдена'
            : 'Самопроверка вернула ошибку';
        _addEp2Log('COMPAT_SELFTEST $result');
      } else {
        await refreshEp2Info();
        ep2InfoNotice = ep2Error == null
            ? 'Радиомодуль отвечает'
            : ep2InfoNotice;
      }
    } catch (error) {
      ep2Error = '$error';
      ep2InfoNotice = 'Самопроверка не пройдена';
      _addEp2Log('SELFTEST ERROR $error');
    }
    notifyListeners();
  }

  void _applyMmUartStats(Map<String, dynamic> stats) {
    ep2Rssi10 = (stats['rssi10'] as num?)?.toInt();
    ep2Snr10 = (stats['snr10'] as num?)?.toInt();
    ep2RttMs = (stats['rttMs'] as num?)?.toInt();
    ep2TxCount = (stats['tx'] as num?)?.toInt();
    ep2RxCount = (stats['rx'] as num?)?.toInt();
    ep2LossCount = (stats['loss'] as num?)?.toInt();
    ep2RetryCount = (stats['retries'] as num?)?.toInt();
  }

  Future<void> pingEp2Neighbor() async {
    final ep2 = _ep2;
    final local = ep2LocalNode;
    if (ep2 == null || !ep2Connected || local == null) return;
    final target = local == 1 ? 2 : 1;
    ep2PingResult = 'PING узла $target…';
    ep2Error = null;
    notifyListeners();
    try {
      final elapsed = await ep2.ping(target);
      ep2PingResult = 'Узел $target · ${elapsed.inMilliseconds} мс';
      _addEp2Log('PING node=$target RTT=${elapsed.inMilliseconds}ms');
    } catch (error) {
      ep2PingResult = 'Узел $target · нет ответа';
      ep2Error = '$error';
      _addEp2Log('PING ERROR node=$target $error');
    }
    notifyListeners();
  }

  Future<void> runRadioHil(int count) async {
    final bench = _radioHilBench;
    final target = radioHilTargetNode;
    if (bench == null || !bench.isAvailable || radioHilRunning) return;
    if (target == null) {
      radioHilError =
          'Не указан второй радиоузел. Выбери контакт с номером EP2/MM-UART '
          'или используй узлы 1 и 2.';
      notifyListeners();
      return;
    }

    radioHilRunning = true;
    radioHilDone = 0;
    radioHilTotal = count;
    radioHilResult = null;
    radioHilError = null;
    _addEp2Log('HIL START target=$target count=$count');
    notifyListeners();

    try {
      final report = await bench.run(
        recipientBinding: target,
        count: count,
        onProgress: (done, total) {
          radioHilDone = done;
          radioHilTotal = total;
          if (done == total || done % 10 == 0) notifyListeners();
        },
      );
      radioHilResult = report.summary();
      _addEp2Log('HIL RESULT ${report.summary()}');
      if (report.statsAfter.isNotEmpty) {
        _applyMmUartStats(report.statsAfter);
      }
    } catch (error) {
      radioHilError = '$error';
      _addEp2Log('HIL ERROR $error');
    } finally {
      radioHilRunning = false;
      notifyListeners();
    }
  }

  Future<void> startEp2WifiUpdate() async {
    final ep2 = _ep2;
    if (ep2 == null || !ep2Connected) return;
    ep2OtaSsid = null;
    ep2OtaPassword = null;
    ep2OtaUrl = null;
    ep2OtaNotice = 'Команда отправляется…';
    _addEp2Log('OTA requested');
    notifyListeners();
    try {
      if (_mmUartActive) {
        final session = _externalRadioSession;
        if (session == null) throw StateError('MM_UART_SESSION_MISSING');
        final result = await session.enterOta();
        ep2OtaSsid = _cleanOptionalString(result['ssid']);
        ep2OtaPassword = _cleanOptionalString(result['password']);
        ep2OtaUrl = _cleanOptionalString(result['url']);
        ep2OtaNotice = ep2OtaSsid == null
            ? 'Режим обновления включён'
            : 'Wi-Fi обновление готово';
        _addEp2Log('ENTER_OTA $result');
      } else {
        await ep2.startWifiUpdate();
        ep2OtaNotice =
            'Команда отправлена. Подождите 2–3 с и проверьте Wi-Fi сеть EP2-OTA-N${ep2LocalNode ?? 'X'}-….';
      }
    } catch (error) {
      ep2OtaNotice = null;
      ep2Error = '$error';
      _addEp2Log('OTA ERROR $error');
    }
    notifyListeners();
  }

  String? _cleanOptionalString(Object? value) {
    if (value == null) return null;
    final clean = '$value'.trim();
    return clean.isEmpty ? null : clean;
  }

  void clearEp2Log() {
    ep2Log.clear();
    notifyListeners();
  }

  void _addEp2Log(String message) {
    if (message.trim().isEmpty) return;
    final time = DateTime.now();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    ep2Log.add('$stamp | $message');
    if (ep2Log.length > 100) {
      ep2Log.removeRange(0, ep2Log.length - 100);
    }
  }

  Object? _resolveMmUartBinding(String mmId) => _resolveEp2Node(mmId);

  Contact? _contactForMmUartBinding(Object binding) {
    final nodeId = binding is num ? binding.toInt() : int.tryParse('$binding');
    return nodeId == null ? null : _contactForEp2Node(nodeId);
  }

  Future<void> _onMmUartTransportEvent(
    MmUartMessageTransportEvent event,
  ) async {
    if (event is MmUartRecipientAck) {
      final contact = _contactForMmUartBinding(event.sourceBinding);
      if (contact == null) {
        _addEp2Log('MM-UART ACK unknown source=${event.sourceBinding}');
        return;
      }
      await _core.recipientDeliveryResult(
        messageId: event.messageId,
        fromMmId: contact.mmId,
        ok: true,
      );
      _addEp2Log('MM-UART ACK ${event.messageId} <- ${contact.mmId}');
      notifyListeners();
      return;
    }

    if (event is MmUartIncomingMessage) {
      final contact = _contactForMmUartBinding(event.sourceBinding);
      final transport = _externalRadio;
      if (contact == null || transport == null) {
        _addEp2Log(
          'MM-UART DROP unknown source=${event.sourceBinding} id=${event.messageId}',
        );
        return;
      }
      try {
        switch (event.messageClass) {
          case 'text':
            final payload = event.payload;
            final text = payload is Map
                ? '${payload['text'] ?? ''}'
                : '$payload';
            if (text.trim().isEmpty) throw const FormatException('TEXT_EMPTY');
            await _core.receiveText(
              messageId: event.messageId,
              fromMmId: contact.mmId,
              text: text,
            );
          case m07DirectEnvelopeClass:
            final payload = event.payload;
            final encoded = payload is Map
                ? '${payload['envelope'] ?? ''}'
                : '$payload';
            if (encoded.trim().isEmpty) {
              throw const FormatException('M07_ENVELOPE_EMPTY');
            }
            await _core.receiveEncryptedDirect(
              messageId: event.messageId,
              fromMmId: contact.mmId,
              encodedEnvelope: encoded,
            );
          case 'map_point':
            final payload = event.payload;
            if (payload is! Map)
              throw const FormatException('MAP_POINT_INVALID');
            await _core.receiveMapPoint(
              messageId: event.messageId,
              fromMmId: contact.mmId,
              payload: jsonEncode(payload),
            );
          default:
            _addEp2Log(
              'MM-UART DROP class=${event.messageClass} id=${event.messageId}',
            );
            return;
        }
        await transport.acknowledgeIncoming(
          messageId: event.messageId,
          recipientBinding: event.sourceBinding,
        );
      } catch (error) {
        _addEp2Log('MM-UART STORE ERROR ${event.messageId} | $error');
        return;
      }
      if (selectedPeerMmId == contact.mmId) await _reloadMessages();
      ep2InfoNotice = event.messageClass == 'map_point'
          ? 'Получена точка от ${contact.displayName}'
          : 'Получено сообщение от ${contact.displayName}';
      notifyListeners();
    }
  }

  void _onMmUartSessionEvent(ExternalRadioSessionEvent event) {
    if (event is ExternalRadioStateEvent) {
      if (_mmUartActive ||
          event.state == 'connecting' ||
          event.state == 'ready') {
        ep2State = event.state;
        if (event.reason != null) ep2Error = event.reason;
      }
    } else if (event is ExternalRadioCapabilitiesEvent) {
      ep2DetectedProtocol = 'mm-uart';
      ep2Protocol = 'MM-UART/1';
      ep2Baud = 115200;
      ep2Firmware = event.info.firmwareVersion;
      ep2Profile = event.capabilities.profileIds.firstOrNull;
      ep2InfoNotice = event.capabilities.supportsMmrp
          ? 'MM-UART/1 · MMRP/1 подтверждён'
          : 'MM-UART/1 без MMRP/1';
    } else if (event is ExternalRadioStatsEvent) {
      _applyMmUartStats(event.stats);
    } else if (event is ExternalRadioErrorEvent) {
      _addEp2Log('MM-UART ERROR ${event.error}');
    } else if (event is ExternalRadioDeviceResetEvent) {
      _addEp2Log('MM-UART DEVICE RESET');
    }
    if (initialized) notifyListeners();
  }

  Future<void> _onLr24Event(TransparentUartRadioEvent event) async {
    if (event is TransparentUartStateEvent) {
      lr24State = event.state;
      lr24Error = event.error;
      _lr24Active = event.state != 'disconnected' && event.state != 'error';
      if (event.state == 'disconnected' || event.state == 'error') {
        lr24PeerMmId = null;
        lr24RttMs = null;
        _lr24DiscoveryTick = 0;
      }
      _addLr24Log(
        'STATE ${event.state}${event.error == null ? '' : ' | ${event.error}'}',
      );
      if (event.state == 'ready') {
        unawaited(_lr24?.discoverPeers());
      }
      notifyListeners();
      return;
    }
    if (event is TransparentUartPeerDiscovered) {
      _markPeerSeen(event.peerMmId);
      final label = event.label.trim();
      if (label.isNotEmpty) _peerLabels[event.peerMmId] = label;
      _peerCapabilities[event.peerMmId] = event.capabilities;
      lr24PeerMmId = event.peerMmId;
      lr24Error = null;
      _lr24DiscoveryTick = 0;
      _addLr24Log(
        'DISCOVER ${event.peerMmId} caps=${event.capabilities.join(',')}',
      );
      notifyListeners();
      return;
    }
    if (event is TransparentUartGroupDescriptor) {
      _markPeerSeen(event.fromMmId);
      final accepted = await _core.upsertGroupDescriptor(
        descriptor: event.descriptor,
        fromMmId: event.fromMmId,
      );
      if (accepted) {
        groups = await _core.groups();
        _addLr24Log(
          'GROUP DESCRIPTOR ${event.descriptor.groupId} '
          'rev=${event.descriptor.revision} <- ${event.fromMmId}',
        );
        lastRadioNotice = 'Добавлена группа «${event.descriptor.displayName}»';
      } else {
        _addLr24Log(
          'DROP GROUP DESCRIPTOR ${event.descriptor.groupId} '
          'rev=${event.descriptor.revision} <- ${event.fromMmId}',
        );
      }
      notifyListeners();
      return;
    }
    if (event is TransparentUartFileProgress) {
      final plan = _preparedFilePlan;
      if (plan != null && plan.manifest.transferId == event.transferId) {
        fileTransferState = event.state;
        fileTransferAckedChunks = event.ackedChunks;
        switch (event.state) {
          case 'idle':
          case 'sendingManifest':
            fileTransferNotice = 'Согласование передачи…';
          case 'sending':
            fileTransferNotice =
                'Отправка: ${event.ackedChunks}/${event.totalChunks} блоков';
          case 'waiting':
            fileTransferNotice =
                'Ожидание подтверждения: ${event.ackedChunks}/${event.totalChunks}';
          case 'pausedLink':
            fileTransferNotice =
                'Ожидает связь · сохранено ${event.ackedChunks}/${event.totalChunks}';
          case 'pausedUser':
            fileTransferNotice =
                'Пауза · сохранено ${event.ackedChunks}/${event.totalChunks}';
          case 'completed':
            fileTransferNotice =
                'Доставлено: ${event.totalChunks}/${event.totalChunks} блоков';
          case 'failed':
            final reason = event.failureReason?.trim();
            fileTransferNotice = reason == null || reason.isEmpty
                ? 'Ошибка передачи'
                : 'Ошибка передачи: ' + reason;
          case 'cancelled':
            fileTransferNotice = 'Передача отменена';
          default:
            fileTransferNotice = 'Передача файла…';
        }
        notifyListeners();
      }
      return;
    }
    if (event is TransparentUartFileReceived) {
      try {
        final storage = _appStorage;
        if (storage == null) throw StateError('storage unavailable');
        final inbox = Directory(storage.root.path + '/received_files');
        await inbox.create(recursive: true);
        final safeName = event.fileName
            .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-я._ -]'), '_')
            .trim();
        final name = safeName.isEmpty ? 'file.bin' : safeName;
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final output = File(inbox.path + '/' + stamp.toString() + '_' + name);
        await output.writeAsBytes(event.bytes, flush: true);
        lastReceivedFileName = name;
        lastReceivedFilePath = output.path;
        fileTransferNotice =
            'Получен файл: ' +
            name +
            ' · ' +
            event.bytes.length.toString() +
            ' Б';
        _addLr24Log(
          'FILE RECEIVED ' +
              event.transferId +
              ' ' +
              name +
              ' ' +
              event.bytes.length.toString() +
              'B',
        );
      } catch (error) {
        fileTransferNotice =
            'Ошибка сохранения полученного файла: ' + error.toString();
        _addLr24Log(
          'FILE RECEIVE STORE ERROR ' +
              event.transferId +
              ' | ' +
              error.toString(),
        );
      }
      notifyListeners();
      return;
    }
    if (event is TransparentUartStatsEvent) {
      lr24TxBytes = event.txBytes;
      lr24RxBytes = event.rxBytes;
      lr24TxFrames = event.txFrames;
      lr24RxFrames = event.rxFrames;
      lr24BadFrames = event.badFrames;
      notifyListeners();
      return;
    }
    if (event is TransparentUartProbeResult) {
      lr24RttMs = event.rttMillis;
      lr24PeerMmId = event.peerMmId;
      _markPeerSeen(event.peerMmId);
      _addLr24Log('PEER ${event.peerMmId} RTT=${event.rttMillis}ms');
      notifyListeners();
      return;
    }
    if (event is TransparentUartRecipientAck) {
      _markPeerSeen(event.fromMmId);
      await _core.recipientDeliveryResult(
        messageId: event.messageId,
        fromMmId: event.fromMmId,
        ok: true,
      );
      _addLr24Log('ACK ${event.messageId} <- ${event.fromMmId}');
      notifyListeners();
      return;
    }
    if (event is TransparentUartChannelReceipt) {
      _markPeerSeen(event.fromMmId);
      final receipts = _channelReceipts.putIfAbsent(
        event.messageId,
        () => <String>{},
      );
      receipts.add(event.fromMmId);
      _addLr24Log(
        'CHANNEL RECEIPT ${event.channelId} ${event.messageId} <- ${event.fromMmId}',
      );
      notifyListeners();
      return;
    }
    if (event is TransparentUartIncomingChannelMessage) {
      _markPeerSeen(event.fromMmId);
      if (event.channelId != 'general') {
        _addLr24Log(
          'DROP unsupported channel=${event.channelId} id=${event.messageId}',
        );
        return;
      }
      if (event.messageClass != 'text' && event.messageClass != 'map_point') {
        _addLr24Log(
          'DROP channel class=${event.messageClass} id=${event.messageId}',
        );
        return;
      }
      try {
        if (event.messageClass == 'map_point') {
          await _core.receiveChannelMapPoint(
            messageId: event.messageId,
            fromMmId: event.fromMmId,
            channelId: event.channelId,
            payload: event.payload,
          );
        } else {
          await _core.receiveChannelText(
            messageId: event.messageId,
            fromMmId: event.fromMmId,
            channelId: event.channelId,
            text: event.payload,
          );
        }
        unawaited(
          _lr24?.acknowledgeChannelIncoming(
            messageId: event.messageId,
            channelId: event.channelId,
            toMmId: event.fromMmId,
          ),
        );
      } catch (error) {
        _addLr24Log('CHANNEL STORE ERROR ${event.messageId} | $error');
        return;
      }
      if (isGeneralChat) await _reloadMessages();
      lastRadioNotice = 'Общий чат · ${displayNameForMmId(event.fromMmId)}';
      notifyListeners();
      return;
    }

    if (event is TransparentUartGroupReceipt) {
      _markPeerSeen(event.fromMmId);
      final result = await _core.receiveGroupReceipt(
        messageId: event.messageId,
        fromMmId: event.fromMmId,
        groupId: event.groupId,
      );
      if (result != null) {
        _groupReceipts
            .putIfAbsent(event.messageId, () => <String>{})
            .add(event.fromMmId);
      }
      _addLr24Log(
        'GROUP RECEIPT ${event.groupId} ${event.messageId} <- ${event.fromMmId}',
      );
      notifyListeners();
      return;
    }
    if (event is TransparentUartIncomingGroupMessage) {
      _markPeerSeen(event.fromMmId);
      if (event.messageClass != 'text' &&
          event.messageClass != m07DirectEnvelopeClass) {
        _addLr24Log(
          'DROP group class=${event.messageClass} id=${event.messageId}',
        );
        return;
      }
      final accepted = event.messageClass == m07DirectEnvelopeClass
          ? await _core.receiveEncryptedGroup(
              messageId: event.messageId,
              fromMmId: event.fromMmId,
              groupId: event.groupId,
              membershipRevision: event.membershipRevision,
              encodedEnvelope: event.payload,
            )
          : await _core.receiveGroupText(
              messageId: event.messageId,
              fromMmId: event.fromMmId,
              groupId: event.groupId,
              membershipRevision: event.membershipRevision,
              text: event.payload,
            );
      if (!accepted) {
        _addLr24Log(
          'DROP group=${event.groupId} peer=${event.fromMmId} id=${event.messageId}',
        );
        return;
      }
      await _lr24?.acknowledgeGroupIncoming(
        messageId: event.messageId,
        groupId: event.groupId,
        toMmId: event.fromMmId,
      );
      if (isGroupChat && activeConversation.id == event.groupId) {
        await _reloadMessages();
      }
      final groupName =
          groups
              .where((g) => g.groupId == event.groupId)
              .firstOrNull
              ?.displayName ??
          'Группа';
      lastRadioNotice = '$groupName · ${displayNameForMmId(event.fromMmId)}';
      notifyListeners();
      return;
    }
    if (event is TransparentUartIncomingMessage) {
      _markPeerSeen(event.fromMmId);
      final contact = contacts
          .where((c) => c.mmId == event.fromMmId)
          .firstOrNull;
      if (contact == null) {
        if (event.messageClass != 'text') {
          _addLr24Log(
            'QUARANTINE unknown class=${event.messageClass} '
            'peer=${event.fromMmId} id=${event.messageId}',
          );
          return;
        }
        try {
          await _core.receiveText(
            messageId: event.messageId,
            fromMmId: event.fromMmId,
            text: event.payload,
          );
          await _lr24?.acknowledgeIncoming(
            messageId: event.messageId,
            toMmId: event.fromMmId,
          );
          await _refreshMessageRequests();
          if (selectedPeerMmId == event.fromMmId) await _reloadMessages();
          lastRadioNotice =
              'Запрос сообщения от ${displayNameForMmId(event.fromMmId)}';
          _addLr24Log(
            'REQUEST unknown peer=${event.fromMmId} id=${event.messageId}',
          );
          notifyListeners();
        } catch (error) {
          _addLr24Log('REQUEST STORE ERROR ${event.messageId} | $error');
        }
        return;
      }
      try {
        switch (event.messageClass) {
          case m07DirectEnvelopeClass:
            await _core.receiveEncryptedDirect(
              messageId: event.messageId,
              fromMmId: event.fromMmId,
              encodedEnvelope: event.payload,
            );
          case 'text':
            await _core.receiveText(
              messageId: event.messageId,
              fromMmId: event.fromMmId,
              text: event.payload,
            );
          case 'map_point':
            await _core.receiveMapPoint(
              messageId: event.messageId,
              fromMmId: event.fromMmId,
              payload: event.payload,
            );
          default:
            _addLr24Log(
              'DROP class=${event.messageClass} id=${event.messageId}',
            );
            return;
        }
        await _lr24?.acknowledgeIncoming(
          messageId: event.messageId,
          toMmId: event.fromMmId,
        );
      } catch (error) {
        _addLr24Log('STORE ERROR ${event.messageId} | $error');
        return;
      }
      if (selectedPeerMmId == event.fromMmId) await _reloadMessages();
      lastRadioNotice = event.messageClass == 'map_point'
          ? 'Получена точка по LR24 от ${contact.displayName}'
          : 'Получено по LR24 от ${contact.displayName}';
      notifyListeners();
    }
  }

  int? _resolveEp2Node(String mmId) =>
      contacts.where((contact) => contact.mmId == mmId).firstOrNull?.ep2NodeId;

  Contact? _contactForEp2Node(int nodeId) =>
      contacts.where((contact) => contact.ep2NodeId == nodeId).firstOrNull;

  Future<void> _onEp2Event(Ep2TransportEvent event) async {
    if ((_mmUartActive || _lr24Active) && event is! Ep2LogEvent) return;
    if (event is Ep2StateEvent) {
      ep2State = event.state;
      ep2Error = event.error;
      if (event.state == 'disconnected') {
        ep2ConnectedDeviceId = null;
        ep2Protocol = 'unknown';
        ep2Baud = null;
        ep2PingResult = null;
        ep2LocalNode = null;
        ep2Firmware = null;
        ep2Profile = null;
        ep2Rssi10 = null;
        ep2Snr10 = null;
        ep2RttMs = null;
        ep2TxCount = null;
        ep2RxCount = null;
        ep2LossCount = null;
        ep2RetryCount = null;
      }
      _addEp2Log(
        'STATE ${event.state}${event.error == null ? '' : ' | ${event.error}'}',
      );
      notifyListeners();
      return;
    }
    if (event is Ep2ProbeEvent) {
      ep2Protocol = switch (event.protocol) {
        RadioUartProtocol.ep2Link => 'EP2 LINK',
        RadioUartProtocol.crsf => 'ELRS / CRSF',
        RadioUartProtocol.unknown => 'Не определён',
      };
      ep2Baud = event.baudRate;
      _addEp2Log(
        'PROBE ${ep2Protocol} baud=${event.baudRate}${event.detail == null ? '' : ' | ${event.detail}'}',
      );
      notifyListeners();
      return;
    }
    if (event is Ep2InfoEvent) {
      ep2DetectedProtocol = 'ep2-link';
      ep2LocalNode = event.nodeId;
      ep2Firmware = event.firmware;
      ep2Profile = event.profile;
      ep2InfoNotice = 'INFO получено · узел ${event.nodeId}';
      _addEp2Log(
        'INFO node=${event.nodeId} fw=${event.firmware} radio=${event.radioState} profile=${event.profile}',
      );
      notifyListeners();
      return;
    }
    if (event is Ep2StatsEvent) {
      ep2Rssi10 = event.rssi10;
      ep2Snr10 = event.snr10;
      ep2RttMs = event.rttMs;
      ep2TxCount = event.tx;
      ep2RxCount = event.rx;
      ep2LossCount = event.loss;
      ep2RetryCount = event.retries;
      final now = DateTime.now();
      ep2InfoNotice =
          'Статистика обновлена · ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      notifyListeners();
      return;
    }
    if (event is Ep2RawBytesEvent) {
      ep2RxBytes += event.bytes.length;
      final shown = event.bytes
          .take(32)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      ep2LastHex = shown;
      if (ep2DetectedProtocol == 'detecting' && event.bytes.isNotEmpty) {
        final first = event.bytes.first;
        if (first == 0xC8 || first == 0xEE || first == 0xEA) {
          ep2DetectedProtocol = 'crsf-like';
        }
      }
      notifyListeners();
      return;
    }
    if (event is Ep2OtaReadyEvent) {
      ep2OtaSsid = event.ssid;
      ep2OtaPassword = event.password;
      ep2OtaUrl = event.url;
      ep2OtaNotice = 'Wi‑Fi обновление запущено.';
      _addEp2Log('OTA READY ' + event.ssid + ' ' + event.url);
      notifyListeners();
      return;
    }
    if (event is Ep2DeliveryEvent) {
      _addEp2Log(
        'RADIO ${event.ok ? 'ACK' : 'NAK'} message=${event.messageId}${event.detail == null ? '' : ' | ${event.detail}'}',
      );
      await _core.recipientDeliveryResult(
        messageId: event.messageId,
        fromMmId: event.recipientMmId,
        ok: event.ok,
        detail: event.detail,
      );
      notifyListeners();
      return;
    }
    if (event is Ep2IncomingText) {
      _addEp2Log('RX_TEXT node=${event.fromNode} seq=${event.sequence}');
      final contact = _contactForEp2Node(event.fromNode);
      if (contact == null) {
        lastRadioNotice =
            '\u0421\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435 EP2 \u043e\u0442 \u0443\u0437\u043b\u0430 ${event.fromNode}: \u0434\u043e\u0431\u0430\u0432\u044c\u0442\u0435 EP2 node \u0432 \u043a\u043e\u043d\u0442\u0430\u043a\u0442';
        notifyListeners();
        return;
      }
      await _core.receiveText(
        messageId: 'ep2-${event.fromNode}-${event.sequence}',
        fromMmId: contact.mmId,
        text: event.text,
      );
      if (selectedPeerMmId == contact.mmId) await _reloadMessages();
      lastRadioNotice =
          '\u041f\u043e\u043b\u0443\u0447\u0435\u043d\u043e EP2 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435 \u043e\u0442 ${contact.displayName}';
      notifyListeners();
      return;
    }
    if (event is Ep2LogEvent) {
      _addEp2Log(event.line);
      notifyListeners();
    }
  }

  int? _resolveNodeNum(String mmId) => contacts
      .where((contact) => contact.mmId == mmId)
      .firstOrNull
      ?.meshtasticNodeNum;

  Contact? _contactForNode(int nodeNum) => contacts
      .where((contact) => contact.meshtasticNodeNum == nodeNum)
      .firstOrNull;

  Future<void> _onMeshtasticEvent(MeshtasticTransportEvent event) async {
    if (event is MeshtasticDeliveryResult) {
      _addRadioLog(
        'ROUTING ${event.ok ? 'ACK' : 'NAK'} message=${event.messageId} reason=${event.errorReason}',
      );
      await _core.recipientDeliveryResult(
        messageId: event.messageId,
        fromMmId: event.recipientMmId,
        ok: event.ok,
        detail: event.ok ? null : 'Meshtastic NAK ${event.errorReason}',
      );
      notifyListeners();
      return;
    }
    if (event is MeshtasticIncomingText) {
      _addRadioLog(
        'TEXT from=!${event.fromNode.toRadixString(16).padLeft(8, '0')} packet=${event.packetId}',
      );
      final contact = _contactForNode(event.fromNode);
      if (contact == null) {
        lastRadioNotice =
            'Сообщение от неизвестного узла !${event.fromNode.toRadixString(16).padLeft(8, '0')} не добавлено в контакты';
        notifyListeners();
        return;
      }
      await _core.receiveText(
        messageId: 'mesh-${event.fromNode}-${event.packetId}',
        fromMmId: contact.mmId,
        text: event.text,
      );
      if (selectedPeerMmId == contact.mmId) await _reloadMessages();
      lastRadioNotice = 'Получено сообщение от ${contact.displayName}';
      notifyListeners();
    }
  }

  int? _parseNodeNum(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final normalized = text.startsWith('!')
        ? text.substring(1)
        : text.toLowerCase().startsWith('0x')
        ? text.substring(2)
        : text;
    final isHex = text.startsWith('!') || text.toLowerCase().startsWith('0x');
    final parsed = int.tryParse(normalized, radix: isHex ? 16 : 10);
    if (parsed == null || parsed <= 0 || parsed > 0xffffffff) {
      throw FormatException('Неверный Meshtastic node ID');
    }
    return parsed;
  }

  int? _parseEp2Node(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1 || parsed > 15) {
      throw FormatException('Номер узла EP2 должен быть от 1 до 15');
    }
    return parsed;
  }

  Future<void> _reloadMessages() async {
    messages = await _core.messagesForConversation(activeConversation);
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdownResources();

  Future<void> _shutdownResources() async {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    await _deliverySub?.cancel();
    await _lanSub?.cancel();
    await _meshtasticSub?.cancel();
    await _androidSub?.cancel();
    await _ep2Sub?.cancel();
    await _externalRadioSub?.cancel();
    await _externalSessionSub?.cancel();
    await _lr24Sub?.cancel();
    await _radioHilBench?.close();
    await _lr24?.close();
    await _externalRadio?.close();
    await _externalRadioSession?.close();
    await _lan?.close();
    await _meshtastic?.close();
    await _ep2?.close();
    await _androidBridge?.close();
    await _usbBridge?.close();
    await _core.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
