from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
activity = (root / 'android/app/src/main/kotlin/org/fpvclub/mesh/MainActivity.kt').read_text()
controller = (root / 'lib/src/application/mesh_app_controller.dart').read_text()
transport = (root / 'lib/platform/lan_transport.dart').read_text()
connection = (root / 'lib/src/features/connection/connection_page.dart').read_text()
help_text = (root / 'lib/src/features/help/help_sheet.dart').read_text()

checks = {
    'manifest internet': 'android.permission.INTERNET' in manifest,
    'manifest local network': 'android.permission.ACCESS_LOCAL_NETWORK' in manifest,
    'android local network channel': 'org.fpvclub.mesh/localnetwork' in activity,
    'android 17 permission': 'ACCESS_LOCAL_NETWORK' in activity,
    'raw udp socket': 'RawDatagramSocket.bind' in transport,
    'broadcast discovery': "255.255.255.255" in transport,
    'lan discover': "'kind': 'discover'" in transport,
    'lan presence': "'kind': 'presence'" in transport,
    'lan ping': "'kind': 'ping'" in transport and "'kind': 'pong'" in transport,
    'lan text': "'kind': 'text'" in transport,
    'lan ack': "'kind': 'ack'" in transport,
    'lan ack timeout': 'LAN_ACK_TIMEOUT' in transport,
    'unknown sender blocked': 'LanUntrustedTextEvent' in transport and 'BLOCK unpaired' in transport,
    'allowed contacts synced': 'setAllowedPeers' in controller,
    'persistent identity': 'loadOrCreateIdentity' in controller,
    'single delivery list includes lan': 'transports.add(lan)' in controller,
    'lan precedes ep2': controller.index('transports.add(lan)') < controller.index('transports.add(ep2)'),
    'ui automatic route': 'Автоматический маршрут' in connection,
    'ui lan active': 'Локальная сеть' in connection and 'Позже · использует ту же очередь' not in connection,
    'ui diagnostics collapsed': connection.count('ExpansionTile(') >= 2,
    'help lan': 'Локальная сеть' in help_text and 'одном hotspot' in help_text and 'SAS-кода' in help_text,
    'ui lan probe': 'Проверить связь' in connection,
    'pairing wire': "'pair_offer'" in transport and "'pair_answer'" in transport and "'pair_confirm'" in transport,
    'verified outbound gate': 'LAN_CONTACT_NOT_VERIFIED' in transport,
    'ui sas pairing': 'Коды совпадают' in connection and 'Сравните код на обоих телефонах' in connection,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('LAN_SOURCE_GATE_FAILED: ' + ', '.join(failed))
print('LAN_SOURCE_GATE_PASS')
