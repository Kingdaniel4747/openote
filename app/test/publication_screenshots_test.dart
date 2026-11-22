// Reproducible public screenshots of the real app, using disposable sample data.
// OPENOTE_PUBLICATION_SHOTS=1 flutter test test/publication_screenshots_test.dart --update-goldens
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/notebook_manager.dart';

import 'support/sqlite.dart';

void main() {
  final enabled = Platform.environment['OPENOTE_PUBLICATION_SHOTS'] == '1';
  setUpAll(() async {
    if (!enabled) return;
    if (!initSqliteForTests()) throw StateError('Screenshots need SQLite');
    for (final family in ['Inter', 'JetBrains Mono']) {
      final folder = family == 'Inter' ? 'inter' : 'jetbrains-mono';
      final prefix = family == 'Inter' ? 'Inter' : 'JetBrainsMono';
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        loader.addFont(
            rootBundle.load('assets/fonts/$folder/$prefix-$weight.ttf'));
      }
      if (family == 'Inter') {
        for (final weight in ['Medium', 'SemiBold']) {
          loader.addFont(
              rootBundle.load('assets/fonts/$folder/$prefix-$weight.ttf'));
        }
      }
      await loader.load();
    }
    final icons = File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
    await loader.load();
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf')))
          .load();
    }
    for (final (family, face) in [
      ('Main', 'Regular'),
      ('Math', 'Italic'),
      ('Size1', 'Regular'),
      ('Size2', 'Regular')
    ]) {
      await (FontLoader('packages/flutter_math_fork/KaTeX_$family')
            ..addFont(rootBundle.load(
                'packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_$family-$face.ttf')))
          .load();
    }
  });

  Future<AppState> seed(WidgetTester t) async {
    late Repository repo;
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('openote-publication-');
    addTearDown(() {
      app.dispose();
      repo.dispose();
      tmp.deleteSync(recursive: true);
    });
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final book = await repo.createNotebook('My semester');
      app = AppState(repo)..notebookId = book.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      app.renameNode(section.id, 'Calculus');
      for (final emptyPage
          in app.nodes.where((n) => n.kind == NodeKind.page).toList()) {
        app.renameNode(emptyPage.id, 'Course overview');
      }
      final page = app.importNode(
          book.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Understanding derivatives',
              position: 'a001'));
      for (final (name, position) in [
        ('Practice problems', 'a002'),
        ('Lecture notes', 'a003'),
        ('Exam preparation', 'a004')
      ]) {
        app.importNode(
            book.id,
            TreeNode(
                kind: NodeKind.page,
                parentId: section.id,
                title: name,
                position: position));
      }
      final curve = Stroke(
          tool: 'pen',
          colorHex: '#6655CC',
          size: 3,
          x: [for (var i = 0; i <= 100; i++) 87 + i * 2.8],
          y: [
            for (var i = 0; i <= 100; i++)
              526 - math.pow((i - 50) / 50, 2) * 120
          ],
          p: List.filled(101, .65));
      Stroke line(List<double> x, List<double> y,
              {String color = '#92929D', double size = 1.5}) =>
          Stroke(
              tool: 'pen',
              colorHex: color,
              size: size,
              x: x.map((v) => v + 52).toList(),
              y: y.map((v) => v + 366).toList(),
              p: List.filled(x.length, .65));
      app.importPage(
          book.id,
          page.id,
          [
            Block(type: BlockType.text, x: 52, y: 40, w: 770, content: {
              'text':
                  '# Think it through. Write it down.\nOne notebook for the things I want to understand.'
            }),
            Block(type: BlockType.text, x: 52, y: 160, w: 370, content: {
              'text':
                  '## Today: derivatives\nA derivative describes how a function changes.\n\n- Read the slope at a single point\n- Connect the equation to its graph\n- Work through the practice sheet'
            }),
            Block(
                type: BlockType.math,
                x: 490,
                y: 164,
                w: 310,
                content: {'latex': r'f(x)=x^2\quad f^{\prime}(x)=2x'}),
            Block(type: BlockType.text, x: 490, y: 265, w: 340, content: {
              'text':
                  '## From the rule to the result\nAt x = 2, the slope is 4.\n\nThe curve describes the function.\nThe straight line shows its tangent.\n\n**Next:** try the same idea with a cubic.'
            }),
            Block(type: BlockType.ink, x: 52, y: 366, w: 355, h: 202, content: {
              'strokes': [
                line([12, 330], [168, 168]).toJson(),
                line([174, 174], [185, 14]).toJson(),
                curve.toJson(),
                line([195, 295], [173, 87], color: '#DC9560', size: 2.5)
                    .toJson(),
              ]
            }),
            Block(type: BlockType.text, x: 52, y: 585, w: 760, content: {
              'text':
                  '## Before the next lecture\n- [x] Review the worked example\n- [ ] Finish the practice problems\n- [ ] Bring one question to the tutorial'
            }),
          ],
          PageProps(background: 'grid'));
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    return app;
  }

  for (final dark in [false, true]) {
    testWidgets('publication study ${dark ? 'dark' : 'light'}', (t) async {
      final app = await seed(t);
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              theme: onoteTheme(dark ? Brightness.dark : Brightness.light),
              debugShowCheckedModeBanner: false,
              home: AppShell(app: app))));
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      await t.tap(find.text('Draw'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
          find.byKey(key),
          matchesGoldenFile(
              '../../website/assets/screenshots/study-${dark ? 'dark' : 'light'}.png'));
      if (!dark) {
        await t.runAsync(() async {
          for (final (name, color) in [
            ('Biology', 'Green'),
            ('Computer Science', 'Indigo'),
            ('Physics', 'Yellow'),
            ('Projects & ideas', 'Coral')
          ]) {
            await app.createNotebook(name);
            app.setNotebookColor(app.notebookId!, color);
          }
        });
        unawaited(showNotebookManager(t.element(find.byType(AppShell)), app));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await expectLater(
            find.byKey(key),
            matchesGoldenFile(
                '../../website/assets/screenshots/notebooks.png'));
        Navigator.of(t.element(find.byType(AppShell))).pop();
        await t.pumpAndSettle();
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 2));
    }, skip: !enabled);
  }
}
