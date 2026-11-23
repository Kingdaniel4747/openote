import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/l10n/app_strings.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/settings_dialog.dart';

import 'support/sqlite.dart';

void main() {
  final screenshots = Platform.environment['OPENOTE_SETTINGS_SHOTS'] == '1';
  setUpAll(() async {
    expect(initSqliteForTests(), isTrue);
    if (!screenshots) return;
    final font = FontLoader('Inter');
    for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/inter/Inter-$face.ttf'));
    }
    await font.load();
    await (FontLoader('Ahem')
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf')))
        .load();
    final icons = File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData())))
        .load();
  });

  for (final (width, height, language, brightness, scale) in [
    (1000.0, 800.0, 'en', Brightness.light, 1.0),
    (1000.0, 800.0, 'de', Brightness.dark, 1.0),
    (540.0, 800.0, 'de', Brightness.light, 1.0),
    (400.0, 640.0, 'de', Brightness.dark, 1.3),
  ]) {
    testWidgets('settings at $width / $language / $brightness / $scale',
        (tester) async {
      late Directory directory;
      late Repository repo;
      late AppState app;
      await tester.runAsync(() async {
        directory = Directory.systemTemp.createTempSync('onote_settings_');
        repo = await Repository.openAt(directory);
        app = AppState(repo);
      });
      addTearDown(() async {
        app.cancelPendingSave();
        await tester.runAsync(() async {
          await repo.flushWorkspace();
          app.dispose();
          await directory.delete(recursive: true);
        });
      });
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: onoteTheme(brightness),
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('de')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () => showSettingsDialog(context, app),
                          child: const Text('Open settings'),
                        ))),
          )));
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Dialog));
      String label(String text) => tr(context, text);
      var currentCategory = 'Appearance';

      Future<void> reveal(Finder target) async {
        for (var i = 0;
            i < 20 && target.hitTestable().evaluate().isEmpty;
            i++) {
          await tester.drag(
              find.byKey(ValueKey('settings-content-$currentCategory')),
              const Offset(0, -120));
          await tester.pumpAndSettle();
        }
        expect(target.hitTestable(), findsOneWidget);
      }

      Future<void> capture(String category) async {
        expect(tester.takeException(), isNull);
        if (!screenshots) return;
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              'build/settings-review/$language-${brightness.name}-${width.toInt()}-$category.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.text(label('Interface language')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await capture('appearance');
      final theme = find.byKey(const ValueKey('settings-theme-dark'));
      await reveal(theme);
      await tester.tap(theme);
      app.cancelPendingSave();
      await tester.pumpAndSettle();
      expect(app.themeMode, ThemeMode.dark);

      for (final category in [
        'Writing and drawing',
        'Navigation',
        'Storage',
        'About',
        'Appearance'
      ]) {
        currentCategory = category;
        final picker = find.byKey(const ValueKey('settings-category-picker'));
        if (picker.evaluate().isNotEmpty) {
          await tester.tap(picker);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label(category)).last);
        } else {
          await tester.tap(find.byKey(ValueKey('settings-category-$category')));
        }
        await tester.pumpAndSettle();
        await capture(category.toLowerCase().replaceAll(' ', '-'));
        if (category == 'Writing and drawing') {
          final previous = app.spellCheckEnabled;
          final row = find.text(label('Spell check'));
          await reveal(row);
          await tester.tap(row);
          app.cancelPendingSave();
          await tester.pumpAndSettle();
          expect(app.spellCheckEnabled, !previous,
              reason: 'the whole labelled row must toggle the setting');
          if (!app.spellCheckEnabled) {
            final handwriting = tester
                .widgetList<SwitchListTile>(find.byType(SwitchListTile))
                .last;
            expect(handwriting.onChanged, isNull,
                reason: 'handwriting checking depends on spell check');
          }
          await reveal(find.text(label('Check language support')));
          await capture('writing-language-support');
        }
        if (category == 'Navigation') {
          final field = find.byType(DropdownButton<bool>);
          await reveal(field);
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label('Above the page')).last);
          app.cancelPendingSave();
          await tester.pumpAndSettle();
          expect(app.sectionTabsAbovePage, isTrue);
        }
      }
      await tester.tap(find.byTooltip(label('Close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
