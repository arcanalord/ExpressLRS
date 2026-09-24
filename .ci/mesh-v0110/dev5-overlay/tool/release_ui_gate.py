from pathlib import Path

root = Path(__file__).resolve().parents[1]
ui_files = [
    root / 'lib/src/features/connection/connection_page.dart',
    root / 'lib/src/features/chats/chats_page.dart',
    root / 'lib/src/features/help/help_sheet.dart',
]
text = '\n'.join(path.read_text() for path in ui_files)
forbidden = [
    'EP2 / SX1280 · USB-UART',
    'EP2 LINK v0.2.0',
    'Узел EP2 (1-15)',
    "child: Text('Расширенная справка')",
]
for item in forbidden:
    assert item not in text, f'user-facing engineering label returned: {item}'
assert 'Радиомодуль · USB' in text
assert "title: const Text('Дополнительно')" in text
assert "title: const Text('Безопасность и технические детали')" in text
print('RELEASE_UI_GATE_PASS')
