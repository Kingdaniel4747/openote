import 'dart:async';
import 'dart:typed_data';
import 'package:pdfrx/pdfrx.dart';

/// Await initialization before using the document API. A fire-and-forget
/// initialize at startup allowed the first import to race the native worker.
abstract final class PdfRuntime {
  static Future<void>? _ready;
  static Future<void> ensureReady() => _ready ??= _initialize();

  static Future<void> _initialize() async {
    try {
      await pdfrxFlutterInitialize().timeout(const Duration(seconds: 30));
    } catch (_) {
      _ready =
          null; // Retry must be able to recover from initialization failure.
      rethrow;
    }
  }

  static Future<PdfDocument> open(Uint8List bytes, String name) async {
    await ensureReady();
    var expired = false;
    final opening = PdfDocument.openData(bytes, sourceName: name);
    // A timed-out native operation may finish later; do not leak its document.
    unawaited(opening.then((doc) async {
      if (expired) await doc.dispose();
    }, onError: (Object _) {}));
    return opening.timeout(const Duration(seconds: 30), onTimeout: () {
      expired = true;
      throw TimeoutException(
          'PDF opening timed out. Check or re-save this PDF.');
    });
  }
}
