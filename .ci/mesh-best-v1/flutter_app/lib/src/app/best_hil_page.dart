import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/message.dart';
import '../m03/android_usb_lr24_link.dart';
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
  final List<String> _log = <String>[];
  String _status = 'Disconnected';
  bool _busy = false;

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
        baudRate: 115200,
      );
      final runtime = BestHilRuntime(
        localMmId: _localMm.text.trim(),
        peerMmId: _peerMm.text.trim(),
        localBinding: _localBinding.text.trim(),
        peerBinding: _peerBinding.text.trim(),
        link: link,
      );
      final subscription = runtime.events.listen(_onHilEvent);
      if (!mounted) {
        await subscription.cancel();
        await runtime.close();
        await link.close();
        return;
      }
      setState(() {
        _link = link;
        _runtime = runtime;
        _eventSubscription = subscription;
        _status = 'LR24 connected @ 115200';
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
      }
    });
  }

  Future<void> _send() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.available) {
      setState(() => _status = 'Connect LR24 first');
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

  Future<void> _disconnect({bool updateUi = true}) async {
    final sub = _eventSubscription;
    final runtime = _runtime;
    final link = _link;
    _eventSubscription = null;
    _runtime = null;
    _link = null;
    await sub?.cancel();
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
            Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: const Text('Connect LR24'),
                ),
                const SizedBox(width: 8),
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
              onPressed: _busy ? null : _send,
              child: const Text('Send'),
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
