import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/spell/spell_checker.dart';
import 'package:openote/spell/writing_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
      () => messenger.setMockMethodCallHandler(WritingServices.channel, null));

  test('German checker sends language and retains UTF-16 offsets', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(WritingServices.channel, (call) async {
      calls.add(call);
      if (call.method == 'start') return 7;
      if (call.method == 'poll')
        return [
          {'start': 3, 'length': 4}
        ];
      return null;
    });
    final errors = await WritingServices.checkText('😀 Feler', 'de-DE');
    expect(errors, [const TextRange(start: 3, end: 7)]);
    expect(calls.first.arguments['language'], 'de-DE');
    expect(calls.last.method, 'cancel');
  }, skip: !Platform.isWindows);

  test('stale recognition jobs are cancelled before polling', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WritingServices.channel, (call) async {
      calls.add(call.method);
      return call.method == 'start' ? 8 : null;
    });
    await expectLater(
        WritingServices.run({'kind': 'ink', 'language': 'de-DE'},
            current: () => false),
        throwsStateError);
    expect(calls, ['start', 'cancel']);
  }, skip: !Platform.isWindows);

  test('missing language is reported and the native job is released', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(WritingServices.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') return 9;
      if (call.method == 'poll')
        return {'error': 'handwriting_language_missing'};
      return null;
    });
    await expectLater(
        WritingServices.run({'kind': 'status', 'language': 'de-DE'}),
        throwsStateError);
    expect(calls.last, 'cancel');
  }, skip: !Platform.isWindows);

  test('masking markdown does not shift German or emoji offsets', () {
    const text = '😀 Deutsch `code_wrong` und Feler';
    final masked = SpellChecker.proseForChecking(text);
    expect(masked.length, text.length);
    expect(masked.indexOf('Feler'), text.indexOf('Feler'));
    expect(masked, isNot(contains('code_wrong')));
  });
}
