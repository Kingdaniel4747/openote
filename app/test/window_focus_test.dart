import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/window_focus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reopening activates the current window maximized without a toggle',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WindowFocus.channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(WindowFocus.channel, null));
    expect(await WindowFocus.raiseSelf(), isTrue);
    expect(await WindowFocus.raiseSelf(), isTrue);
    expect(calls, ['ensureMaximized', 'show', 'ensureMaximized', 'show']);
  }, skip: !Platform.isWindows);
}
