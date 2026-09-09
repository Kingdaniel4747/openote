import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows' native, whole-desktop selection overlay. It deliberately lives
/// behind a tiny boundary: Flutter can render its own window, but cannot read
/// the pixels of another program after Openote has been hidden.
class ScreenCapture {
  ScreenCapture._();

  static const _channel = MethodChannel('openote/screen_capture');

  /// Lets the user mark a screen rectangle and returns its PNG bytes.
  /// Unsupported platforms simply have no native implementation yet.
  static Future<Uint8List?> selectRegion() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return null;
    return _channel.invokeMethod<Uint8List>('selectRegion');
  }
}
