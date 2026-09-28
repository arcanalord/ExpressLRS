import 'package:flutter/material.dart';

import '../../../core/models.dart';

import '../../application/mesh_app_controller.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({
    required this.controller,
    required this.onOpenMapPoint,
    super.key,
  });

  final MeshAppController controller;
  final ValueChanged<MapPoint> onOpenMapPoint;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final TextEditingController _composer = TextEditingController();

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
    DeliveryState.waitingAck => 'Ждём ACK',
    DeliveryState.delivered => 'Доставлено',
    DeliveryState.broadcasted => 'Отправлено',
    DeliveryState.noRoute => 'Нет маршрута',
    DeliveryState.retryWait => 'Повтор',
    DeliveryState.expired => 'Истёк TTL',
    DeliveryState.failed => 'Ошибка',
    DeliveryState.cancelled => 'Отменено',
    null => 'Сохранено',
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final contacts = _ContactList(controller: widget.controller);
    final conversation = _ConversationPane(
      controller: widget.controller,
      composer: _composer,
      stateLabel: stateLabel,
      onOpenMapPoint: widget.onOpenMapPoint,
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 150, child: contacts),
                const SizedBox(height: 12),
                Expanded(child: conversation),
              ],
            ),
    );
  }
}

class _ContactList extends StatelessWidget {
  const _ContactList({required this.controller});
  final MeshAppController controller;

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
        onTap: controller.selectGeneralChat,
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
          onTap: () => controller.selectGroup(group.groupId),
        ),
      if (controller.contacts.isNotEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Приватные', style: TextStyle(fontWeight: FontWeight.w700)),
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
          trailing: contact.verified
              ? const Icon(Icons.verified_user_outlined, size: 18)
              : null,
          onTap: () => controller.selectContact(contact.mmId),
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
          trailing: IconButton(
            tooltip: 'Добавить контакт',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => controller.addNearbyPeerAsContact(mmId),
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
                  tooltip: 'Добавить контакт вручную',
                  onPressed: () => _showAddContact(context, controller),
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
  final name = TextEditingController();
  final selected = <String>{};
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Новая группа'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Название группы'),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final contact in controller.contacts)
                      CheckboxListTile(
                        value: selected.contains(contact.mmId),
                        title: Text(contact.displayName),
                        subtitle: Text(contact.mmId),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selected.add(contact.mmId);
                            } else {
                              selected.remove(contact.mmId);
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: selected.isEmpty || name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true && context.mounted) {
    await controller.createGroup(
      displayName: name.text,
      memberMmIds: selected,
    );
  }
  name.dispose();
}

Future<void> _showAddContact(
  BuildContext context,
  MeshAppController controller,
) async {
  final name = TextEditingController();
  final mmId = TextEditingController();
  final node = TextEditingController();
  final ep2Node = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Добавить контакт'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            TextField(
              controller: mmId,
              decoration: const InputDecoration(
                labelText: 'Код контакта (MM-ID)',
              ),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Дополнительно'),
              subtitle: const Text('Привязка транспорта при ручной настройке'),
              children: [
                TextField(
                  controller: node,
                  decoration: const InputDecoration(
                    labelText: 'Meshtastic node ID',
                    hintText: '!a1b2c3d4',
                  ),
                ),
                TextField(
                  controller: ep2Node,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    try {
      await controller.addLocalContact(
        mmId: mmId.text,
        displayName: name.text,
        meshtasticNode: node.text,
        ep2Node: ep2Node.text,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
      }
    }
  }
  name.dispose();
  mmId.dispose();
  node.dispose();
  ep2Node.dispose();
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.controller,
    required this.composer,
    required this.stateLabel,
    required this.onOpenMapPoint,
  });

  final MeshAppController controller;
  final TextEditingController composer;
  final String Function(DeliveryState?) stateLabel;
  final ValueChanged<MapPoint> onOpenMapPoint;

  @override
  Widget build(BuildContext context) {
    final isGeneral = controller.isGeneralChat;
    final isGroup = controller.isGroupChat;
    final contact = controller.selectedContact;
    final group = controller.selectedGroup;
    if (!isGeneral && !isGroup && contact == null) {
      return const Card(child: Center(child: Text('Нет выбранного контакта')));
    }
    if (isGroup && group == null) {
      return const Card(child: Center(child: Text('Группа недоступна')));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              child: isGeneral
                  ? const Icon(Icons.forum_outlined, size: 20)
                  : isGroup
                  ? const Icon(Icons.groups_2_outlined, size: 20)
                  : Text(
                      contact!.displayName.characters.first.toUpperCase(),
                    ),
            ),
            title: Text(
              isGeneral
                  ? 'Общий чат'
                  : isGroup
                  ? group!.displayName
                  : contact!.displayName,
            ),
            subtitle: Text(
              isGeneral
                  ? 'Все совместимые узлы · в сети: ${controller.generalOnlineCount}'
                  : isGroup
                  ? '${group!.memberMmIds.length} участников · LR24: 1→1 транспорт'
                  : 'Контакт существует независимо от текущего маршрута',
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
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
                                                controller.channelReceiptCountFor(
                                                      message.messageId,
                                                    ) >
                                                    0
                                          ? 'Получено: ${controller.channelReceiptCountFor(message.messageId)}'
                                          : stateLabel(state),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                    if (!isGeneral &&
                                        !isGroup &&
                                        state == DeliveryState.waitingAck) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Тестовый ACK',
                                        onPressed: () => controller.acknowledge(
                                          message.messageId,
                                        ),
                                        icon: const Icon(
                                          Icons.done_all,
                                          size: 16,
                                        ),
                                      ),
                                    ],
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
                  IconButton.filled(
                    tooltip: 'Отправить',
                    onPressed: controller.busy
                        ? null
                        : () async {
                            final text = composer.text;
                            if (text.trim().isEmpty) return;
                            composer.clear();
                            await controller.sendText(text);
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
