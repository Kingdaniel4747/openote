import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/l10n/app_strings.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/planner_panel.dart';

import 'support/sqlite.dart';

void main() {
  final shots = Platform.environment['OPENOTE_PLANNER_SHOTS'] == '1';
  setUpAll(() async {
    expect(initSqliteForTests(), isTrue);
    if (!shots) return;
    for (final family in ['Inter', 'Ahem']) {
      final font = FontLoader(family);
      for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        font.addFont(rootBundle.load('assets/fonts/inter/Inter-$face.ttf'));
      }
      await font.load();
    }
    final icons = File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData())))
        .load();
  });

  for (final (height, brightness, scale) in [
    (900.0, Brightness.light, 1.0),
    (720.0, Brightness.dark, 1.0),
    (560.0, Brightness.light, 1.3),
  ]) {
    testWidgets(
        'planner overview and inline editor at $height / $brightness / $scale',
        (tester) async {
      late AppState app;
      late Repository repo;
      late Directory directory;
      final tomorrow =
          DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
      const title = 'Mathe: Aufgaben 3 bis 5';
      const notes = 'Seite 42 lesen und alle Rechenwege aufschreiben.\n'
          'Erkläre bei Aufgabe 5, warum deine Lösung stimmt.\n'
          'Bringe deine Notizen zur nächsten Stunde mit.';
      await tester.runAsync(() async {
        directory =
            Directory.systemTemp.createTempSync('openote_planner_layout_');
        repo = await Repository.openAt(directory);
        final notebook = await repo.createNotebook('Schule');
        app = AppState(repo)..notebookId = notebook.id;
        app.reloadNodes();
        await app.selectPage(
            app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
        app.planner.reminders.add(
            text: '$title — $notes',
            at: tomorrow,
            allDay: true,
            category: 'homework',
            color: 'blue',
            notebookId: notebook.id,
            pageId: app.pageId);
      });
      tester.view.physicalSize = Size(1000, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        app.cancelPendingSave();
        await tester.runAsync(() async {
          await repo.flushWorkspace();
          app.dispose();
          await directory.delete(recursive: true);
        });
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de'), Locale('en')],
        theme: onoteTheme(brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: app,
                builder: (context, _) => Row(children: [
                      const Spacer(),
                      RepaintBoundary(
                          key: boundary, child: PlannerPanel(app: app)),
                    ]))),
      ));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(PlannerPanel));
      String label(String text) => tr(context, text);
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        if (!shots) return;
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              'build/planner-review/${brightness.name}-${height.toInt()}-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('overview');
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      await capture('entry');
      final noteField = find.byKey(const ValueKey('planner-entry-notes'));
      for (var i = 0; i < 15 && noteField.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -100));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<TextField>(noteField).controller!.text, notes);
      await tester.enterText(noteField, '$notes\nZusätzliche Notiz');
      await tester.pumpAndSettle();
      expect(find.text(label('Show all')).hitTestable(), findsOneWidget);
      expect(find.text(label('Save')).hitTestable(), findsOneWidget);
      await capture('notes');
      await tester.tap(find.text(label('Save')));
      app.cancelPendingSave();
      await tester.pumpAndSettle();
      expect(app.planner.reminders.all.single.text,
          '$title — $notes\nZusätzliche Notiz');
      await tester.tap(find.byTooltip(label('Current month')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      await tester.tap(find
          .byKey(ValueKey('planner-day-${now.year}-${now.month}-${now.day}')));
      await tester.pumpAndSettle();
      await capture('new-homework');
      await tester.pumpWidget(const SizedBox());
      app.cancelPendingSave();
      app.dispose();
    });
  }
}
