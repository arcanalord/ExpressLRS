import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../m03/android_usb_lr24_link.dart';
import '../m03/mmrp1_control.dart';
import 'best_hil_runtime.dart';

final class BestHilPage extends StatefulWidget {
  const BestHilPage({super.key});

  @override
  State<BestHilPage> createState() => _BestHilPageState();
}

final class _BestHilPageState extends State<BestHilPage> {
  final _localMm = TextEditingController(text: 'mm:a');
  final _peerMm = TextEditingController(text: 'mm:b');
  final _localBinding = TextEditingController(text: 'lr24:A');
  final _peerBinding = TextEditingController(text: 'lr24:B');
  final _message = TextEditingController();

  List<UsbSerialDeviceInfo> _devices = const <UsbSerialDeviceInfo>[];
  int? _selectedDeviceId;
  AndroidUsbLr24ByteStreamLink? _link;
  BestHilRuntime? _runtime;
  StreamSubscription<BestHilEvent>? _eventSubscription;
  StreamSubscription<Mmrp1LinkEvent>? _linkEventSubscription;
  final List<String> _log = <String>[];
  String _status = 'Disconnected';
  bool _busy = false;
  bool _testRunning = false;
  int _testCompleted = 0;
  int _testDelivered = 0;
  int _testFailed = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(_refreshDevices());
    }
  }

  void _presetA() {
    setState(() {
      _localMm.text = 'mm:a';
      _peerMm.text = 'mm:b';
      _localBinding.text = 'lr24:A';
      _peerBinding.text = 'lr24:B';
    });
  }

  void _presetB() {
    setState(() {
      _localMm.text = 'mm:b';
      _peerMm.text = 'mm:a';
      _localBinding.text = 'lr24:B';
      _peerBinding.text = 'lr24:A';
    });
  }

  Future<void> _refreshDevices() async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _status = 'USB HIL is Android-only');
      return;
    }
    setState(() => _busy = true);
    try {
      final devices = await AndroidUsbLr24ByteStreamLink.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        if (_selectedDeviceId == null ||
            !devices.any((d) => d.deviceId == _selectedDeviceId)) {
          _selectedDeviceId = devices.isEmpty ? null : devices.first.deviceId;
        }
        _status = devices.isEmpty
            ? 'No USB serial devices'
            : 'Found ${devices.length} USB device(s)';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'USB scan failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final deviceId = _selectedDeviceId;
    if (deviceId == null) {
      setState(() => _status = 'Select an LR24 USB device');
      return;
    }
    setState(() => _busy = true);
    try {
      await _disconnect(updateUi: false);
      final link = await AndroidUsbLr24ByteStreamLink.connect(
        deviceId: deviceId,
        baudRate: 57600,
      );
      final runtime = BestHilRuntime(
        localMmId: _localMm.text.trim(),
        peerMmId: _peerMm.text.trim(),
        localBinding: _localBinding.text.trim(),
        peerBinding: _peerBinding.text.trim(),
        link: link,
      );
      final subscription = runtime.events.listen(_onHilEvent);
      final linkSubscription = runtime.linkEvents.listen(_onLinkEvent);
      if (!mounted) {
        await subscription.cancel();
        await linkSubscription.cancel();
        await runtime.close();
        await link.close();
        return;
      }
      setState(() {
        _link = link;
        _runtime = runtime;
        _eventSubscription = subscription;
        _linkEventSubscription = linkSubscription;
        _status = 'LR24 connected @ 57600';
        _log.insert(0, '[LINK] connected USB device $deviceId');
      });
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Connect failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onHilEvent(BestHilEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case BestHilIncomingText():
          _log.insert(0, '[IN ${event.senderMmId}] ${event.text}');
        case BestHilDeliveryUpdate():
          _log.insert(
            0,
            '[DELIVERY ${event.messageId}] ${event.state.name}',
          );
        case BestHilTestProgress():
          _testCompleted = event.completed;
          _testDelivered = event.delivered;
          _testFailed = event.failed;
      }
    });
  }

  void _onLinkEvent(Mmrp1LinkEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case Mmrp1PeerReady():
          _status = 'Peer ready: ${event.mmId}';
          _log.insert(0, '[PEER] ${event.mmId} ${event.label}');
        case Mmrp1ProbeResult():
          _log.insert(0, '[PING] ${event.mmId} ${event.rttMs} ms');
      }
    });
  }

  Future<void> _findPeer() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.available) {
      setState(() => _status = 'Connect LR24 first');
      return;
    }
    try {
      await runtime.discoverPeer();
      if (mounted) setState(() => _status = 'Discovery sent...');
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Discovery failed: $error');
    }
  }

  Future<void> _probePeer() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.peerReady) {
      setState(() => _status = 'Find Peer first');
      return;
    }
    try {
      await runtime.probePeer();
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Probe failed: $error');
    }
  }

  Future<void> _send() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.available) {
      setState(() => _status = 'Connect LR24 first');
      return;
    }
    if (!runtime.peerReady) {
      setState(() => _status = 'Find Peer first');
      return;
    }
    final text = _message.text.trim();
    if (text.isEmpty) return;
    try {
      final record = await runtime.sendText(text);
      if (!mounted) return;
      setState(() {
        _log.insert(
          0,
          '[OUT ${record.message.messageId}] ${record.state.name}: $text',
        );
        _message.clear();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Send failed: $error');
    }
  }

  Future<void> _runTest100() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.available) {
      setState(() => _status = 'Connect LR24 first');
      return;
    }
    if (!runtime.peerReady) {
      setState(() => _status = 'Find Peer first');
      return;
    }
    setState(() {
      _testRunning = true;
      _testCompleted = 0;
      _testDelivered = 0;
      _testFailed = 0;
      _status = 'Test 100 running...';
      _log.insert(0, '[TEST100] started');
    });
    try {
      final result = await runtime.runTextTest();
      if (!mounted) return;
      setState(() {
        _status = result.passed
            ? 'Test 100 PASS'
            : 'Test 100 FAIL: ${result.delivered}/${result.total} delivered';
        _log.insert(
          0,
          '[TEST100] ${result.passed ? 'PASS' : 'FAIL'} '
          '${result.delivered}/${result.total} delivered, '
          '${result.failed} failed, '
          '${result.elapsed.inMilliseconds} ms',
        );
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Test 100 error: $error';
          _log.insert(0, '[TEST100] ERROR $error');
        });
      }
    } finally {
      if (mounted) setState(() => _testRunning = false);
    }
  }

  Future<void> _disconnect({bool updateUi = true}) async {
    final sub = _eventSubscription;
    final linkSub = _linkEventSubscription;
    final runtime = _runtime;
    final link = _link;
    _eventSubscription = null;
    _linkEventSubscription = null;
    _runtime = null;
    _link = null;
    await sub?.cancel();
    await linkSub?.cancel();
    await runtime?.close();
    await link?.close();
    if (mounted && updateUi) {
      setState(() {
        _status = 'Disconnected';
        _log.insert(0, '[LINK] disconnected');
      });
    }
  }

  String _deviceLabel(UsbSerialDeviceInfo device) {
    String hex(int? value) =>
        value == null ? '----' : value.toRadixString(16).padLeft(4, '0');
    final name = device.productName?.trim();
    return '${name == null || name.isEmpty ? 'USB serial' : name} '
        '[${hex(device.vendorId)}:${hex(device.productId)}] #${device.deviceId}';
  }

  @override
  void dispose() {
    unawaited(_disconnect(updateUi: false));
    _localMm.dispose();
    _peerMm.dispose();
    _localBinding.dispose();
    _peerBinding.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Messenger Best v1')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'EXPERIMENTAL HIL — DEV M07, NOT PRODUCTION',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text('M02 -> M07 -> M12 -> PreparedTransportPacket -> M03'),
            const SizedBox(height: 4),
            const Text('Release status: experimental / not production'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _presetA,
                  child: const Text('Node A'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _presetB,
                  child: const Text('Node B'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _refreshDevices,
                  child: const Text('Refresh USB'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _localMm,
              decoration: const InputDecoration(labelText: 'Local MM-ID'),
            ),
            TextField(
              controller: _peerMm,
              decoration: const InputDecoration(labelText: 'Peer MM-ID'),
            ),
            TextField(
              controller: _localBinding,
              decoration: const InputDecoration(labelText: 'Local LR24 binding'),
            ),
            TextField(
              controller: _peerBinding,
              decoration: const InputDecoration(labelText: 'Peer LR24 binding'),
            ),
            const SizedBox(height: 12),
            DropdownButton<int>(
              value: _selectedDeviceId,
              isExpanded: true,
              hint: const Text('Select USB serial device'),
              items: [
                for (final device in _devices)
                  DropdownMenuItem<int>(
                    value: device.deviceId,
                    child: Text(
                      _deviceLabel(device),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _selectedDeviceId = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: const Text('Connect LR24'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _findPeer,
                  child: const Text('Find Peer'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _probePeer,
                  child: const Text('Probe'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: $_status'),
            const Divider(height: 28),
            TextField(
              controller: _message,
              decoration: const InputDecoration(
                labelText: 'Test text',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy || _testRunning ? null : _send,
              child: const Text('Send'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy || _testRunning ? null : _runTest100,
              child: Text(
                _testRunning
                    ? 'Test 100: $_testCompleted/100'
                    : 'Test 100',
              ),
            ),
            if (_testRunning || _testCompleted > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Delivered $_testDelivered | Failed $_testFailed',
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'HIL log',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final line in _log.take(40))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line),
              ),
          ],
        ),
      ),
    );
  }
}
