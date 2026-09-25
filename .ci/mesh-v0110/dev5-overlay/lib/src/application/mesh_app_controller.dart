import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/app_storage.dart';
import '../../core/delivery.dart';
import '../../core/identity_crypto.dart';
import '../../core/messenger_core.dart';
import '../../core/models.dart';
import '../../platform/android_local_network_bridge.dart';
import '../../platform/android_secure_identity_bridge.dart';
import '../../platform/android_meshtastic_bridge.dart';
import '../../platform/android_usb_serial_bridge.dart';
import '../../platform/android_usb_mm_uart_host_link.dart';
import '../../platform/ep2_uart_transport.dart';
import '../../platform/mm_uart_external_radio_session.dart';
import '../../platform/mm_uart_message_transport.dart';
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
  Ep2UartTransport? _ep2;
  MmUartExternalRadioSession? _externalRadioSession;
  MmUartMessageTransport? _externalRadio;
  bool _mmUartActive = false;
  StreamSubscription<DeliveryEnvelope>? _deliverySub;
  StreamSubscription<LanTransportEvent>? _lanSub;
  StreamSubscription<MeshtasticTransportEvent>? _meshtasticSub;
  StreamSubscription<AndroidMeshtasticEvent>? _androidSub;
  StreamSubscription<Ep2TransportEvent>? _ep2Sub;
  StreamSubscription<MmUartMessageTransportEvent>? _externalRadioSub;
  StreamSubscription<ExternalRadioSessionEvent>? _externalSessionSub;
  Timer? _maintenanceTimer;
  bool _maintenanceBusy = false;
  bool _usbMaintenanceBusy = false;
  int _usbMaintenanceTick = 0;
  DateTime? _lastUsbAutoConnectAttempt;
  int? _lastUsbAutoConnectDeviceId;

  bool initialized = false;
  bool busy = false;
  String? selectedPeerMmId;
  List<Contact> contacts = const [];
  List<ConversationMessage> messages = const [];
  MapPoint? requestedMapFocus;
  int mapFocusSerial = 0;

  String ownMmId = '';
  String ownDeviceLabel = '';
  String ownFingerprint = '';
  String identitySeedStorage = '';
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

  bool get hasLocalNetworkPermissionBridge => _localNetworkBridge != null;
  bool get lanReady => _lan?.isAvailable ?? false;
  bool get lanPermissionGranted => lanPermission['granted'] == true;
  bool get lanPermissionRequired => lanPermission['required'] == true;
  bool get hasAndroidMeshtastic => _androidBridge != null;
  bool get radioConnected => _androidBridge?.connected ?? false;
  bool get hasEp2Uart => _usbBridge != null;
  bool get mmUartActive => _mmUartActive;
  bool get ep2Connected =>
      (_externalRadio?.isAvailable ?? false) || (_ep2?.isAvailable ?? false);
  String? get externalRadioFamily =>
      _externalRadioSession?.snapshot().info?.radioFamily;
  String? get externalBoardId =>
      _externalRadioSession?.snapshot().info?.boardId;
  bool get externalRadioSupportsMmrp =>
      _externalRadioSession?.supportsMmrp == true;

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

    final storage = AppStorage(root);
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
    identitySeedStorage = _identity.seedStorage;
    await storage.savePublicIdentityMetadata(
      mmId: ownMmId,
      label: ownDeviceLabel,
      fingerprint: ownFingerprint,
      identityPublicKey: _identity.identityPublicKeyB64,
      agreementPublicKey: _identity.agreementPublicKeyB64,
      seedStorage: identitySeedStorage,
    );

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
      transports.add(externalRadio);
      _externalRadioSub = externalRadio.events.listen(_onMmUartTransportEvent);
      _externalSessionSub = externalSession.events.listen(_onMmUartSessionEvent);

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
    );
    await _core.restore();
    _deliverySub = _core.deliveryChanges.listen((_) {
      if (initialized) notifyListeners();
    });

    contacts = await _core.contacts();
    if (contacts.isEmpty) {
      await _core.saveContact(
        const Contact(
          mmId: 'mm:demo-alexey',
          displayName: '\u0410\u043b\u0435\u043a\u0441\u0435\u0439',
        ),
      );
      contacts = await _core.contacts();
    }
    lan.setAllowedPeers(
      contacts
          .where((contact) => contact.verified)
          .map((contact) => contact.mmId),
    );
    selectedPeerMmId = contacts.firstOrNull?.mmId;
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
    final id = selectedPeerMmId;
    if (id == null) return null;
    return contacts.where((c) => c.mmId == id).firstOrNull;
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
    final peer = selectedPeerMmId;
    if (peer == null || busy) return;
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
      await _core.sendMapPoint(peerMmId: peer, point: point);
      await _reloadMessages();
      requestMapFocus(point);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectContact(String mmId) async {
    selectedPeerMmId = mmId;
    await _reloadMessages();
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    final peer = selectedPeerMmId;
    if (peer == null || text.trim().isEmpty || busy) return;
    busy = true;
    notifyListeners();
    try {
      await _core.sendText(peerMmId: peer, text: text);
      await _reloadMessages();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> acknowledge(String messageId) async {
    final peer = selectedPeerMmId;
    if (peer == null) return;
    await _core.acknowledge(messageId, peer);
    notifyListeners();
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
    _lan?.setAllowedPeers(
      contacts
          .where((contact) => contact.verified)
          .map((contact) => contact.mmId),
    );
    selectedPeerMmId = cleanId;
    await _reloadMessages();
    notifyListeners();
  }

  bool hasContact(String mmId) =>
      contacts.any((contact) => contact.mmId == mmId);

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

      if (!ep2Connected && ep2ConnectedDeviceId == null && devices.length == 1) {
        final device = devices.single;
        final now = DateTime.now();
        final last = _lastUsbAutoConnectAttempt;
        final sameDevice = _lastUsbAutoConnectDeviceId == device.deviceId;
        final backoffActive =
            sameDevice &&
            last != null &&
            now.difference(last) < const Duration(seconds: 8);
        if (!backoffActive) {
          _lastUsbAutoConnectAttempt = now;
          _lastUsbAutoConnectDeviceId = device.deviceId;
          _addEp2Log('AUTO hotplug device=${device.deviceId}');
          unawaited(connectEp2(device.deviceId));
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
      if (event.messageClass != 'map_point') {
        _addLanLog('DROP CLASS ${event.messageClass} ${event.messageId}');
        return;
      }
      try {
        await _core.receiveMapPoint(
          messageId: event.messageId,
          fromMmId: event.fromMmId,
          payload: event.payload,
        );
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

  Future<void> connectEp2(int deviceId) async {
    final ep2 = _ep2;
    final session = _externalRadioSession;
    final bridge = _usbBridge;
    if (ep2 == null || session == null || bridge == null || busy) return;
    busy = true;
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
        ep2InfoNotice = ep2Error == null ? 'Радиомодуль отвечает' : ep2InfoNotice;
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

  Future<void> _onMmUartTransportEvent(MmUartMessageTransportEvent event) async {
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
            final text = payload is Map ? '${payload['text'] ?? ''}' : '$payload';
            if (text.trim().isEmpty) throw const FormatException('TEXT_EMPTY');
            await _core.receiveText(
              messageId: event.messageId,
              fromMmId: contact.mmId,
              text: text,
            );
          case 'map_point':
            final payload = event.payload;
            if (payload is! Map) throw const FormatException('MAP_POINT_INVALID');
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
      if (_mmUartActive || event.state == 'connecting' || event.state == 'ready') {
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

  int? _resolveEp2Node(String mmId) =>
      contacts.where((contact) => contact.mmId == mmId).firstOrNull?.ep2NodeId;

  Contact? _contactForEp2Node(int nodeId) =>
      contacts.where((contact) => contact.ep2NodeId == nodeId).firstOrNull;

  Future<void> _onEp2Event(Ep2TransportEvent event) async {
    if (_mmUartActive && event is! Ep2LogEvent) return;
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
      final shown = event.bytes.take(32)
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
    final peer = selectedPeerMmId;
    messages = peer == null ? const [] : await _core.messagesFor(peer);
  }

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    _deliverySub?.cancel();
    _lanSub?.cancel();
    _meshtasticSub?.cancel();
    _androidSub?.cancel();
    _ep2Sub?.cancel();
    _externalRadioSub?.cancel();
    _externalSessionSub?.cancel();
    _externalRadio?.close();
    _externalRadioSession?.close();
    _lan?.close();
    _meshtastic?.close();
    _ep2?.close();
    _androidBridge?.close();
    _usbBridge?.close();
    _core.close();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
