import 'package:flutter/services.dart';

final class AndroidDiagnosticsExportBridge {
  const AndroidDiagnosticsExportBridge();

  static const MethodChannel _channel =
      MethodChannel('org.fpvclub.mesh/diagnostics');

  Future<String?> exportText({
    required String fileName,
    required String text,
  }) =>
      _channel.invokeMethod<String>(
        'exportText',
        <String, Object?>{
          'fileName': fileName,
          'text': text,
        },
      );
}
