import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/contact_card.dart';
import '../../../core/models.dart';

import '../../application/mesh_app_controller.dart';
import '../contacts/contact_share_dialog.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({
    required this.controller,
    required this.onOpenMapPoint,
    required this.onOpenMapComposer,
    super.key,
  });

  final MeshAppController controller;
  final ValueChanged<MapPoint> onOpenMapPoint;
  final VoidCallback onOpenMapComposer;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final TextEditingController _composer = TextEditingController();
  bool _mobileConversationOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ChatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _composer.dispose();
    super.dispose();
  }

  String stateLabel(DeliveryState? state) => switch (state) {
    DeliveryState.queued => 'В очереди',
    DeliveryState.sending => 'Отправка',
    DeliveryState.waitingAck => 'Ожидает подтверждения',
    DeliveryState.delivered => 'Доставлено',
    DeliveryState.broadcasted => 'Отправлено',
    DeliveryState.noRoute => 'Нет маршрута',
    DeliveryState.retryWait => 'Повторная отправка',
    DeliveryState.expired => 'Истёк TTL',
    DeliveryState.failed => 'Ошибка',
    DeliveryState.cancelled => 'Отменено',
    null => 'Сохранено',
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final contacts = _ContactList(
      controller: widget.controller,
      onOpenConversation: () {
        if (!wide && mounted) {
          setState(() => _mobileConversationOpen = true);
        }
      },
    );
    final conversation = _ConversationPane(
      controller: widget.controller,
      composer: _composer,
      stateLabel: stateLabel,
      onOpenMapPoint: widget.onOpenMapPoint,
      onOpenMapComposer: widget.onOpenMapComposer,
      onBack: wide
          ? null
          : () {
              if (mounted) setState(() => _mobileConversationOpen = false);
            },
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 310, child: contacts),
                const SizedBox(width: 12),
                Expanded(child: conversation),
              ],
            )
          : _mobileConversationOpen
          ? conversation
          : contacts,
    );
  }
}

class _ContactList extends StatelessWidget {
  const _ContactList({
    required this.controller,
    required this.onOpenConversation,
  });

  final MeshAppController controller;
  final VoidCallback onOpenConversation;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      ListTile(
        selected: controller.isGeneralChat,
        leading: const CircleAvatar(
          child: Icon(Icons.forum_outlined, size: 20),
        ),
        title: const Text('Общий чат'),
        subtitle: Text(
          'Все совместимые узлы · в сети: ${controller.generalOnlineCount}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          controller.selectGeneralChat();
          onOpenConversation();
        },
      ),
      if (controller.groups.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Группы', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      for (final group in controller.groups)
        ListTile(
          selected:
              controller.isGroupChat &&
              controller.activeConversation.id == group.groupId,
          leading: const CircleAvatar(
            child: Icon(Icons.groups_2_outlined, size: 20),
          ),
          title: Text(group.displayName),
          subtitle: Text(
            '${group.memberMmIds.length} участников',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            controller.selectGroup(group.groupId);
            onOpenConversation();
          },
        ),
      if (controller.contacts.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Приватные',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      for (final contact in controller.contacts)
        ListTile(
          selected:
              !controller.isGeneralChat &&
              !controller.isGroupChat &&
              contact.mmId == controller.selectedPeerMmId,
          leading: CircleAvatar(
            child: Text(contact.displayName.characters.first.toUpperCase()),
          ),
          title: Text(contact.displayName),
          subtitle: Text(
            contact.mmId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (contact.verified)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.verified_user_outlined, size: 18),
                ),
              IconButton(
                tooltip: 'Переименовать контакт',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () async {
                  final name = await _promptContactName(
                    context,
                    initialName: contact.displayName,
                    title: 'Переименовать контакт',
                    subtitle: contact.mmId,
                  );
                  if (name == null || name == contact.displayName) return;
                  await controller.renameContact(
                    mmId: contact.mmId,
                    displayName: name,
                  );
                },
              ),
            ],
          ),
          onTap: () {
            controller.selectContact(contact.mmId);
            onOpenConversation();
          },
        ),
      if (controller.messageRequestPeerMmIds.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Запросы',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      for (final mmId in controller.messageRequestPeerMmIds)
        ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.mark_chat_unread_outlined, size: 20),
          ),
          title: Text(controller.displayNameForMmId(mmId)),
          subtitle: const Text(
            'Не в контактах · можно прочитать, ответить или добавить',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Добавить контакт',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () async {
              final name = await _promptContactName(
                context,
                initialName: controller.displayNameForMmId(mmId),
                title: 'Добавить контакт',
                subtitle: mmId,
              );
              if (name == null) return;
              await controller.addNearbyPeerAsContact(mmId, displayName: name);
            },
          ),
          onTap: () {
            controller.selectDirectPeer(mmId);
            onOpenConversation();
          },
        ),
      if (controller.nearbyPeerMmIds.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Рядом', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      for (final mmId in controller.nearbyPeerMmIds)
        ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.radar_outlined, size: 20),
          ),
          title: Text(controller.displayNameForMmId(mmId)),
          subtitle: Text(
            '$mmId · LR24/сеть',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            controller.selectDirectPeer(mmId);
            onOpenConversation();
          },
          trailing: IconButton(
            tooltip: 'Добавить контакт',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () async {
              final name = await _promptContactName(
                context,
                initialName: controller.displayNameForMmId(mmId),
                title: 'Добавить контакт',
                subtitle: mmId,
              );
              if (name == null) return;
              await controller.addNearbyPeerAsContact(mmId, displayName: name);
            },
          ),
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Чаты',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Создать группу',
                  onPressed: controller.contacts.isEmpty
                      ? null
                      : () => _showCreateGroup(context, controller),
                  icon: const Icon(Icons.group_add_outlined),
                ),
                IconButton(
                  tooltip: 'Добавить контакт',
                  onPressed: () => _showContactActions(context, controller),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
              ],
            ),
          ),
          Expanded(child: ListView(children: items)),
        ],
      ),
    );
  }
}

Future<void> _showCreateGroup(
  BuildContext context,
  MeshAppController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _CreateGroupDialog(controller: controller),
  );
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog({required this.controller});

  final MeshAppController controller;

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final TextEditingController _name = TextEditingController();
  final Set<String> _selected = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving || _selected.isEmpty || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.controller.createGroup(
        displayName: _name.text,
        memberMmIds: _selected,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать группу: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая группа'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Название группы'),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final contact in widget.controller.contacts)
                    CheckboxListTile(
                      value: _selected.contains(contact.mmId),
                      title: Text(contact.displayName),
                      subtitle: Text(contact.mmId),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(contact.mmId);
                                } else {
                                  _selected.remove(contact.mmId);
                                }
                              });
                            },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving || _selected.isEmpty || _name.text.trim().isEmpty
              ? null
              : _create,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }
}

Future<void> _showContactActions(
  BuildContext context,
  MeshAppController controller,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _AddContactPage(controller: controller),
    ),
  );
}

class _AddContactPage extends StatefulWidget {
  const _AddContactPage({required this.controller});

  final MeshAppController controller;

  @override
  State<_AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<_AddContactPage> {
  bool _busy = false;

  Future<void> _importContact(String raw) async {
    if (_busy) return;
    try {
      final card = ContactCard.parse(raw);
      if (!mounted) return;
      Contact? existing;
      for (final contact in widget.controller.contacts) {
        if (contact.mmId == card.mmId.trim()) {
          existing = contact;
          break;
        }
      }
      final name = await _promptContactName(
        context,
        initialName: existing?.displayName ?? card.displayName,
        title: existing == null ? 'Сохранить контакт' : 'Обновить контакт',
        subtitle: card.mmId.trim(),
        helperText: existing == null
            ? 'Имя хранится только у вас и не меняет MM-ID или ключи.'
            : 'Ключевые данные обновятся из карточки, локальное имя останется вашим.',
      );
      if (!mounted || name == null) return;

      setState(() => _busy = true);
      await widget.controller.addContactCard(raw, displayNameOverride: name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Контакт добавлен' : 'Контакт обновлён',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить контакт: $error')),
      );
    }
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ContactQrScannerPage()),
    );
    if (!mounted || raw == null) return;
    await _importContact(raw);
  }

  Future<void> _paste() async {
    final raw = (await Clipboard.getData('text/plain'))?.text;
    if (!mounted) return;
    if (raw == null || raw.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Буфер обмена пуст')));
      return;
    }
    await _importContact(raw);
  }

  Future<void> _manual() async {
    final added = await _showAddContact(context, widget.controller);
    if (mounted && added) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить контакт')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Показать мой QR'),
                  subtitle: const Text(
                    'Другой телефон отсканирует ваш контакт',
                  ),
                  enabled: !_busy,
                  onTap: _busy
                      ? null
                      : () => showOwnContactCardDialog(
                          context,
                          widget.controller,
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('Сканировать чужой QR'),
                  subtitle: const Text('Сканировать карточку и выбрать имя'),
                  enabled: !_busy,
                  onTap: _busy ? null : _scan,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.content_paste_go_outlined),
                  title: const Text('Вставить код'),
                  subtitle: const Text('Проверить карточку и выбрать имя'),
                  enabled: !_busy,
                  onTap: _busy ? null : _paste,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Ввести вручную'),
                  subtitle: const Text('MM-ID и привязка транспорта'),
                  enabled: !_busy,
                  onTap: _busy ? null : _manual,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Обычно достаточно QR. Параметры Meshtastic и радиомодуля находятся в ручном вводе.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Future<String?> _promptContactName(
  BuildContext context, {
  required String initialName,
  required String title,
  required String subtitle,
  String? helperText,
}) => showDialog<String>(
  context: context,
  builder: (dialogContext) => _ContactNameDialog(
    initialName: initialName,
    title: title,
    subtitle: subtitle,
    helperText: helperText,
  ),
);

class _ContactNameDialog extends StatefulWidget {
  const _ContactNameDialog({
    required this.initialName,
    required this.title,
    required this.subtitle,
    this.helperText,
  });

  final String initialName;
  final String title;
  final String subtitle;
  final String? helperText;

  @override
  State<_ContactNameDialog> createState() => _ContactNameDialogState();
}

class _ContactNameDialogState extends State<_ContactNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName.trim(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final clean = _controller.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Имя контакта',
                helperText: widget.helperText,
                helperMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: clean.isEmpty ? null : _submit,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ContactQrScannerPage extends StatefulWidget {
  const _ContactQrScannerPage();

  @override
  State<_ContactQrScannerPage> createState() => _ContactQrScannerPageState();
}

class _ContactQrScannerPageState extends State<_ContactQrScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать контакт')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (_done) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.trim().isNotEmpty) {
                  _done = true;
                  Navigator.of(context).pop(raw);
                  break;
                }
              }
            },
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Наведи камеру на QR-код контакта Mesh Messenger.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _showAddContact(
  BuildContext context,
  MeshAppController controller,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _AddContactDialog(controller: controller),
      ) ??
      false;
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog({required this.controller});

  final MeshAppController controller;

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _mmId = TextEditingController();
  final TextEditingController _node = TextEditingController();
  final TextEditingController _ep2Node = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _mmId.dispose();
    _node.dispose();
    _ep2Node.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty || _mmId.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Укажите имя и MM-ID')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.addLocalContact(
        mmId: _mmId.text,
        displayName: _name.text,
        meshtasticNode: _node.text,
        ep2Node: _ep2Node.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ввести контакт вручную'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Имя'),
              ),
              TextField(
                controller: _mmId,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Код контакта (MM-ID)',
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Дополнительно'),
                subtitle: const Text('Meshtastic и привязка радиомодуля'),
                children: [
                  TextField(
                    controller: _node,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Meshtastic node ID',
                      hintText: '!a1b2c3d4',
                    ),
                  ),
                  TextField(
                    controller: _ep2Node,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Узел радиомодуля (1-15)',
                      hintText: '2',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.controller,
    required this.composer,
    required this.stateLabel,
    required this.onOpenMapPoint,
    required this.onOpenMapComposer,
    this.onBack,
  });

  final MeshAppController controller;
  final TextEditingController composer;
  final String Function(DeliveryState?) stateLabel;
  final ValueChanged<MapPoint> onOpenMapPoint;
  final VoidCallback onOpenMapComposer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final isGeneral = controller.isGeneralChat;
    final isGroup = controller.isGroupChat;
    final isDirect = controller.isDirectChat;
    final contact = controller.selectedContact;
    final directPeerMmId = controller.selectedPeerMmId;
    final directDisplayName = controller.selectedDirectDisplayName;
    final group = controller.selectedGroup;
    if (isDirect && directPeerMmId == null) {
      return const Card(child: Center(child: Text('Нет выбранного собеседника')));
    }
    if (!isGeneral && !isGroup && !isDirect) {
      return const Card(child: Center(child: Text('Нет выбранного чата')));
    }
    if (isGroup && group == null) {
      return const Card(child: Center(child: Text('Группа недоступна')));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Назад к чатам',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ListTile(
            leading: CircleAvatar(
              child: isGeneral
                  ? const Icon(Icons.forum_outlined, size: 20)
                  : isGroup
                  ? const Icon(Icons.groups_2_outlined, size: 20)
                  : Text(
                      directDisplayName.isEmpty
                          ? '?'
                          : directDisplayName.characters.first.toUpperCase(),
                    ),
            ),
            title: Text(
              isGeneral
                  ? 'Общий чат'
                  : isGroup
                  ? group!.displayName
                  : directDisplayName,
            ),
            subtitle: Text(
              isGeneral
                  ? 'Открытый канал · в сети: ${controller.generalOnlineCount}'
                  : isGroup
                  ? '${group!.memberMmIds.length} участников'
                  : contact == null
                  ? 'Не в контактах · запрос/прямой чат'
                  : contact.verified
                  ? 'Контакт проверен'
                  : 'Контакт не проверен',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: controller.messages.isEmpty
                ? const Center(child: Text('История пуста'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.messages.length,
                    itemBuilder: (context, index) {
                      final message = controller.messages[index];
                      final state = message.outgoing
                          ? controller.deliveryStateFor(message.messageId)
                          : null;
                      return Align(
                        alignment: message.outgoing
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 560),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          decoration: BoxDecoration(
                            color: message.outgoing
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((isGeneral || isGroup) &&
                                  !message.outgoing &&
                                  message.senderMmId != null) ...[
                                Text(
                                  controller.displayNameForMmId(
                                    message.senderMmId!,
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 3),
                              ],
                              if (message.isMapPoint) ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        message.mapPoint!.label.isEmpty
                                            ? 'Точка на карте'
                                            : message.mapPoint!.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${message.mapPoint!.latitude.toStringAsFixed(6)}, ${message.mapPoint!.longitude.toStringAsFixed(6)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (message.mapPoint!.note.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(message.mapPoint!.note),
                                ],
                                const SizedBox(height: 4),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () =>
                                      onOpenMapPoint(message.mapPoint!),
                                  icon: const Icon(
                                    Icons.map_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('На карте'),
                                ),
                              ] else
                                Text(message.text),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  if (message.outgoing) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      isGroup
                                          ? controller.groupDeliveryLabelFor(
                                              message.messageId,
                                            )
                                          : isGeneral &&
                                                state ==
                                                    DeliveryState.broadcasted &&
                                                controller
                                                        .channelReceiptCountFor(
                                                          message.messageId,
                                                        ) >
                                                    0
                                          ? 'Получено: ${controller.channelReceiptCountFor(message.messageId)}'
                                          : stateLabel(state),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (controller.preparedFileName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(controller.preparedFileName!),
                        subtitle: Text(
                          _formatFileBytes(controller.preparedFileBytes ?? 0) +
                              ' · ' +
                              _fileTransferStateLabel(controller),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (controller.fileTransferPausedByUser)
                              IconButton(
                                tooltip: 'Продолжить',
                                onPressed: controller.fileTransferCanContinue
                                    ? controller.continuePreparedFileTransfer
                                    : null,
                                icon: const Icon(Icons.play_arrow_rounded),
                              )
                            else if (controller.fileTransferCanPause)
                              IconButton(
                                tooltip: 'Пауза',
                                onPressed: controller.pausePreparedFileTransfer,
                                icon: const Icon(Icons.pause_rounded),
                              ),
                            if (controller.fileTransferSending)
                              IconButton(
                                tooltip: 'Отменить передачу',
                                onPressed:
                                    controller.cancelPreparedFileTransfer,
                                icon: const Icon(Icons.stop_circle_outlined),
                              )
                            else if (controller.fileTransferCanRetry)
                              IconButton(
                                tooltip: 'Повторить передачу',
                                onPressed: controller.sendPreparedSmallFile,
                                icon: const Icon(Icons.refresh),
                              )
                            else
                              IconButton(
                                tooltip: 'Убрать',
                                onPressed: controller.clearPreparedFile,
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      ),
                      if (controller.fileTransferSending ||
                          controller.fileTransferProgress > 0) ...[
                        LinearProgressIndicator(
                          value: controller.fileTransferProgress,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(controller.fileTransferProgress * 100).round()}%',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                      if (controller.fileTransferNotice != null)
                        Text(
                          controller.fileTransferNotice!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (controller.advancedMode) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${controller.preparedFileChunks ?? 0} блоков · '
                          '${controller.preparedFileProfile.name}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: composer,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Добавить',
                    onPressed: controller.busy
                        ? null
                        : () => _showAttachmentMenu(
                            context,
                            controller,
                            onOpenMapComposer,
                          ),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: controller.preparedFileName != null
                        ? controller.fileTransferCanRetry
                              ? 'Повторить отправку файла'
                              : 'Отправить файл'
                        : 'Отправить',
                    onPressed: controller.busy
                        ? null
                        : () async {
                            try {
                              if (controller.preparedFileName != null) {
                                await controller.sendPreparedSmallFile();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        controller.fileTransferNotice ??
                                            'Файл отправлен',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                              final text = composer.text;
                              if (text.trim().isEmpty) return;
                              composer.clear();
                              await controller.sendText(text);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Ошибка отправки: ' + error.toString(),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    icon: controller.busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showAttachmentMenu(
  BuildContext context,
  MeshAppController controller,
  VoidCallback onOpenMapComposer,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Файл'),
            subtitle: const Text('Документ или другой файл · до 100 КБ'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Местоположение'),
            subtitle: const Text('Выбрать точку на карте'),
            onTap: () => Navigator.pop(context, 'location'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  if (action == 'location') {
    onOpenMapComposer();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нажмите место на карте, чтобы отправить точку'),
        ),
      );
    }
    return;
  }
  if (action == 'file') {
    await _pickSmallFile(context, controller);
  }
}

Future<void> _pickSmallFile(
  BuildContext context,
  MeshAppController controller,
) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('Не удалось прочитать выбранный файл');
    }
    if (bytes.length > 100 * 1024) {
      throw ArgumentError('Пока лимит 100 КБ');
    }
    await controller.prepareSmallFile(
      fileName: file.name,
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.fileTransferNotice ?? 'Файл подготовлен'),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Файл не выбран: ' + error.toString())),
      );
    }
  }
}

String _formatFileBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  final kib = bytes / 1024;
  if (kib < 100) return '${kib.toStringAsFixed(1)} КБ';
  return '${kib.round()} КБ';
}

String _fileTransferStateLabel(MeshAppController controller) {
  return switch (controller.fileTransferState) {
    'prepared' => 'Готов к отправке',
    'sendingManifest' => 'Подготовка канала',
    'sending' => 'Отправляется',
    'waiting' => 'Ожидает подтверждения',
    'pausedLink' => 'Ожидает связь',
    'pausedUser' => 'Пауза',
    'completed' => 'Доставлен',
    'failed' => 'Ошибка',
    'cancelled' => 'Отменён',
    _ => 'Файл',
  };
}
