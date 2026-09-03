import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Windows performs recognition locally on a background thread. Polling keeps
/// callbacks away from the native messenger during window teardown.
abstract final class WritingServices {
  static const channel = MethodChannel('openote/writing_services');
  static Future<Object?> run(Map<String, Object?> args,
      {bool Function()? current}) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows writing services');
    final id = await channel.invokeMethod<int>('start', args);
    if (id == null) throw StateError('No writing job');
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        if (current != null && !current()) {
          throw StateError('Superseded writing job');
        }
        final result = await channel.invokeMethod<Object?>('poll', id);
        if (result is Map && result['error'] != null) {
          throw StateError(result['error'].toString());
        }
        if (result != null) return result;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw TimeoutException('Writing service timed out');
    } finally {
      try {
        await channel.invokeMethod<void>('cancel', id);
      } catch (_) {}
    }
  }

  static Future<List<TextRange>> checkText(String text, String language) async {
    final result =
        await run({'kind': 'text', 'language': language, 'text': text});
    return [
      for (final item in result as List)
        if (item is Map && item['start'] is num && item['length'] is num)
          TextRange(
              start: (item['start'] as num).toInt(),
              end: (item['start'] as num).toInt() +
                  (item['length'] as num).toInt())
    ];
  }
}
