import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/mesh_app_controller.dart';

Future<void> showOwnContactCardDialog(
  BuildContext context,
  MeshAppController controller,
) async {
  final payload = controller.ownContactCardPayload;
  final label = controller.ownDeviceLabel.trim().isEmpty
      ? 'Mesh Messenger'
      : controller.ownDeviceLabel.trim();

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Мой QR и MM-ID'),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 244,
                  height: 244,
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: SizedBox.square(
                    dimension: 220,
                    child: QrImageView(
                      data: payload,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'MM-ID',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              SelectableText(
                controller.ownMmId,
                textAlign: TextAlign.center,
              ),
              if (controller.ownFingerprint.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Fingerprint: ' + controller.ownFingerprint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: controller.ownMmId),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('MM-ID скопирован')),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Копировать MM-ID'),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: payload));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Код контакта скопирован')),
              );
            }
          },
          icon: const Icon(Icons.content_copy),
          label: const Text('Копировать код'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}
