// Public screenshots render the actual ScannerHome UI without a camera,
// network access, user files or a real pairing token.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote_scanner/main.dart';

void main() {
  final enabled = Platform.environment['OPENOTE_PUBLICATION_SHOTS'] == '1';
  testWidgets('publication scanner home', (t) async {
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData())))
        .load();
    final font = File('../app/assets/fonts/inter/Inter-Regular.ttf');
    await (FontLoader('Roboto')
          ..addFont(Future.value(font.readAsBytesSync().buffer.asByteData())))
        .load();
    t.view.physicalSize = const Size(420, 840);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'offline-screenshot'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(key: key, child: const OpenoteScannerApp()),
    );
    await t.pumpAndSettle();
    expect(find.text('Was möchtest du hinzufügen?'), findsOneWidget);
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('../../website/assets/screenshots/scanner-actions.png'),
    );
    Navigator.of(t.element(find.text('Was möchtest du hinzufügen?'))).pop();
    await t.pumpAndSettle();
    expect(find.text('Connect to an Openote page'), findsOneWidget);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('../../website/assets/screenshots/scanner-home.png'),
    );
    await t.pumpWidget(const SizedBox.shrink());
  }, skip: !enabled);
}
