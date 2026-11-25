import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/ink_eraser.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/ink/handwriting_profile.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/handwriting_dialog.dart';
import 'package:openote/ui/handwriting_pad.dart';

import 'support/sqlite.dart';

void main() {
  var sqlite = false;
  late Directory directory;
  late Repository repo;
  late AppState app;
  WidgetTester? activeTester;
  setUpAll(() async {
    sqlite = initSqliteForTests();
    for (final family in ['Inter', 'Roboto', 'Ahem']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf')))
          .load();
    }
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk != null) {
      final icons = File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')
              ..addFont(
                  Future.value(icons.readAsBytesSync().buffer.asByteData())))
            .load();
      }
    }
  });
  setUp(() async {
    activeTester = null;
    if (!sqlite) return;
    directory =
        Directory.systemTemp.createTempSync('openote_handwriting_beta_');
    repo = await Repository.openAt(directory);
    final notebook = await repo.createNotebook('Beta');
    app = AppState(repo)..notebookId = notebook.id;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    app.spellCheckEnabled = false;
  });
  tearDown(() async {
    if (!sqlite) return;
    Future<void> close() async {
      await app.flushSave();
      await repo.flushWorkspace();
      app.cancelPendingSave();
      app.dispose();
      repo.dispose();
      directory.deleteSync(recursive: true);
    }

    if (activeTester case final tester?) {
      await tester.runAsync(close);
    } else {
      await close();
    }
  });

  Stroke sample(double left) => Stroke(
      tool: 'pen',
      colorHex: '#000000',
      size: 2.5,
      x: [left, left + 40],
      y: [48, 112],
      p: [.3, .7],
      tx: [.1, .2],
      ty: [.2, .3],
      t: [0, 50],
      strokeStart: 0);

  Future<void> settle(WidgetTester tester) async {
    // Real storage I/O belongs outside the widget test's fake clock.
    app.cancelPendingSave();
    await tester.pumpAndSettle();
  }

  HandwritingProfile completedProfile({String? except}) {
    final profile = HandwritingProfile();
    for (final rune in HandwritingProfile.characters.runes) {
      final character = String.fromCharCode(rune);
      if (character != except) profile.addSample(character, [sample(20)]);
    }
    return profile;
  }

  Future<void> shot(WidgetTester t, GlobalKey key, String name) async {
    if (Platform.environment['OPENOTE_BETA_SHOTS'] != '1') return;
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'overview shows all characters; selected variants replace, delete and add without shifting other samples',
      (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    t.view.physicalSize = const Size(1100, 950);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final profile = completedProfile();
    for (var i = 0; i < 4; i++) {
      profile.addSample('a', [
        Stroke(
            tool: 'pen',
            colorHex: 'auto',
            size: 2.5,
            x: [40, 160],
            y: [60.0 + i * 8, 112])
      ]);
    }
    final originalIds = profile.samples['a']!.map((v) => v.single.id).toList();
    app.saveHandwritingProfile(profile);
    app.cancelPendingSave();
    final boundaryKey = GlobalKey();
    await t.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(body: HandwritingDialog(app: app)))));
    await settle(t);
    await t.tap(find.text('Edit handwriting'));
    await settle(t);
    for (final rune in HandwritingProfile.characters.runes) {
      expect(
          find.byKey(ValueKey('handwriting-tile-${String.fromCharCode(rune)}')),
          findsOneWidget);
    }
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await shot(t, boundaryKey, 'handwriting-overview');
    await t.tap(find.byKey(const ValueKey('handwriting-tile-a')));
    await settle(t);
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('handwriting-variant-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('handwriting-new-variant')), findsNothing);
    await shot(t, boundaryKey, 'handwriting-variants');
    await t.tap(find.byKey(const ValueKey('handwriting-variant-3')));
    await t.pump();
    final pad = t.state<HandwritingPadState>(find.byType(HandwritingPad));
    expect(pad.strokes.single.id, originalIds[3]);
    await t.tap(find.byKey(const ValueKey('handwriting-retry')));
    await t.pump();
    expect(pad.strokes, isEmpty);
    expect(app.handwritingProfile.samples['a']![3].single.id, originalIds[3],
        reason: 'Retry only clears the draft until Save');
    final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final pen =
        await t.startGesture(rect.center, kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(30, 20));
    await pen.up();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('handwriting-save-next')));
    await settle(t);
    final replaced = app.handwritingProfile.samples['a']!;
    expect(replaced, hasLength(5));
    expect(replaced[3].single.id, isNot(originalIds[3]));
    expect(replaced[0].single.id, originalIds[0]);
    expect(replaced[4].single.id, originalIds[4]);
    expect(find.byKey(const ValueKey('handwriting-tile-a')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('handwriting-tile-a')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('handwriting-variant-1')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('handwriting-delete-variant')));
    await settle(t);
    expect(app.handwritingProfile.samples['a'], hasLength(4));
    expect(app.handwritingProfile.samples['a']![1].single.id, originalIds[2]);
    expect(
        find.byKey(const ValueKey('handwriting-new-variant')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('handwriting-new-variant')));
    await t.pump();
    expect(t.state<HandwritingPadState>(find.byType(HandwritingPad)).strokes,
        isEmpty);
    final newRect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final newPen =
        await t.startGesture(newRect.center, kind: PointerDeviceKind.stylus);
    await newPen.moveBy(const Offset(25, 20));
    await newPen.up();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('handwriting-save-next')));
    await settle(t);
    expect(app.handwritingProfile.samples['a'], hasLength(5));
    expect(
        app.handwritingProfile.samples['a']!.first.single.id, originalIds[0]);
    expect(app.handwritingProfile.samples['a']![3].single.id, originalIds[4]);
    await t.pumpWidget(const SizedBox());
  });

  test('profile persists across reopening the workspace', () async {
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    app.saveHandwritingProfile(
        HandwritingProfile()..addSample('a', [sample(20)]));
    await repo.flushWorkspace();
    final reopened = await Repository.openAt(directory);
    final restored = AppState(reopened);
    expect(restored.handwritingProfile.samples['a']!.single.single.p, [.3, .7]);
    expect(restored.handwritingProfile.isComplete, isFalse);
    expect(restored.handwritingProfile.pendingCharacters.first, 'b');
    restored.dispose();
    reopened.dispose();
  });

  test('selected ink changes brush only, supports undo and survives save',
      () async {
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    final chosen =
        app.addBlock(Block(type: BlockType.ink, x: 20, y: 48, content: {
      'strokes': [sample(20).toJson()]
    }));
    final other =
        app.addBlock(Block(type: BlockType.ink, x: 100, y: 48, content: {
      'strokes': [sample(100).toJson()]
    }));
    final before = (chosen.content['strokes'] as List).single as Map;
    (before['brush'] as Map)['futureField'] = 'preserve';
    await app.flushSave(); // Exercise edits to previously persisted ink too.
    app.setTool(Tool.lasso);
    app.select(chosen.id);
    app.recolorSelectedInk('#FF0000');
    app.setInkSize(6);
    Stroke read(String id) => Stroke.fromJson(Map<String, dynamic>.from(
        (app.blocks.firstWhere((b) => b.id == id).content['strokes'] as List)
            .single as Map));
    expect(read(chosen.id).colorHex, '#FF0000');
    expect(read(chosen.id).size, 6);
    expect(read(chosen.id).x, [20, 60]);
    expect(read(chosen.id).p, [.3, .7]);
    expect(read(other.id).size, 2.5);
    expect(read(other.id).colorHex, '#000000');
    expect(
        ((chosen.content['strokes'] as List).single['brush']
            as Map)['futureField'],
        'preserve');
    app.undo();
    expect(read(chosen.id).size, 2.5);
    expect(read(chosen.id).colorHex, '#FF0000');
    app.undo();
    expect(read(chosen.id).colorHex, '#000000');
    app.redo();
    app.redo();
    await app.flushSave();
    final reloaded = AppState(repo)..notebookId = app.notebookId;
    reloaded.reloadNodes();
    await reloaded.selectPage(app.pageId!);
    final saved = Stroke.fromJson(Map<String, dynamic>.from((reloaded.blocks
            .firstWhere((b) => b.id == chosen.id)
            .content['strokes'] as List)
        .single as Map));
    expect(saved.colorHex, '#FF0000');
    expect(saved.size, 6);
    reloaded.dispose();
  });

  test('generated ink is inserted, erasable and saved without changing samples',
      () async {
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    final profile = completedProfile();
    final generated =
        profile.generate('aa', origin: const Offset(100, 200), height: 64);
    final block = app.insertHandwriting(generated)!;
    expect(block.type, BlockType.ink);
    expect(app.selectedIds, contains(block.id));
    final first = Stroke.fromJson(Map<String, dynamic>.from(
        (block.content['strokes'] as List).first as Map));
    final parts =
        eraseStroke(first, const Offset(120, 280), const Offset(120, 280), 5)!;
    expect(parts, hasLength(2));
    block.content['strokes'] = [
      for (final s in parts) s.toJson(),
      generated.last.toJson()
    ];
    app.updateBlock(block);
    await app.flushSave();
    expect(app.saveError, isNull);
    expect(profile.samples['a']!.single.single.x, [20, 60]);
    app.undo();
    expect(app.blocks.where((b) => b.id == block.id), isEmpty);
  });

  testWidgets('record with pen, save, generate preview and insert normal ink',
      (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    t.view.physicalSize = const Size(1000, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    app.saveHandwritingProfile(completedProfile(except: 'a'));
    app.cancelPendingSave();
    await t.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: Scaffold(body: HandwritingButton(app: app))));
    await t.tap(find.byKey(const ValueKey('handwriting-beta')));
    await settle(t);
    final pad = find.byKey(const ValueKey('handwriting-pad'));
    final rect = t.getRect(pad);
    final pen = await t.startGesture(
        rect.topLeft + Offset(rect.width * .3, rect.height * .3),
        kind: PointerDeviceKind.stylus);
    await pen.moveTo(rect.topLeft + Offset(rect.width * .5, rect.height * .7));
    await pen.up();
    await t.pump();
    expect(find.byKey(const ValueKey('handwriting-text')), findsNothing);
    await t.tap(find.byKey(const ValueKey('handwriting-save-next')));
    await settle(t);
    expect(app.handwritingProfile.samples['a'], hasLength(1));
    expect(app.handwritingProfile.isComplete, isTrue);
    await t.enterText(find.byKey(const ValueKey('handwriting-text')), 'aa');
    await settle(t);
    final insert = find.byKey(const ValueKey('handwriting-insert'));
    await t.ensureVisible(insert);
    await t.tap(insert);
    await settle(t);
    expect(find.byType(HandwritingDialog), findsNothing);
    final ink = app.blocks.where((b) => b.type == BlockType.ink).single;
    expect(ink.content['strokes'], hasLength(2));
    expect(app.selectedIds, contains(ink.id));
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('setup confirms, advances, resumes and keeps conversion locked',
      (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: HandwritingDialog(app: app))));
    await settle(t);
    expect(find.byKey(const ValueKey('handwriting-text')), findsNothing);
    expect(find.byKey(const ValueKey('handwriting-insert')), findsNothing);
    expect(
        t
            .widget<FilledButton>(
                find.byKey(const ValueKey('handwriting-save-next')))
            .onPressed,
        isNull);
    final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final pen = await t.startGesture(rect.center - const Offset(20, 20),
        kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(30, 40));
    await pen.up();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('handwriting-save-next')));
    await settle(t);
    expect(
        t
            .widget<Text>(
                find.byKey(const ValueKey('handwriting-current-character')))
            .data,
        'b');
    expect(app.handwritingProfile.samples['a'], hasLength(1));
    expect(app.handwritingProfile.isComplete, isFalse);
    expect(find.byKey(const ValueKey('handwriting-text')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: HandwritingDialog(app: app))));
    await settle(t);
    expect(
        t
            .widget<Text>(
                find.byKey(const ValueKey('handwriting-current-character')))
            .data,
        'b');
    expect(find.byType(DropdownButtonFormField<String>), findsNothing,
        reason: 'setup cannot skip unrecorded characters');
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'every setup character is confirmed before automatic conversion opens',
      (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    t.view.physicalSize = const Size(1000, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: Scaffold(body: HandwritingDialog(app: app))));
    await settle(t);
    for (final rune in HandwritingProfile.characters.runes) {
      expect(find.byKey(const ValueKey('handwriting-text')), findsNothing);
      expect(
          t
              .widget<Text>(
                  find.byKey(const ValueKey('handwriting-current-character')))
              .data,
          String.fromCharCode(rune));
      final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
      final pen = await t.startGesture(rect.center - const Offset(20, 20),
          kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(30, 40));
      await pen.up();
      await t.pump();
      await t.tap(find.byKey(const ValueKey('handwriting-save-next')));
      await settle(t);
    }
    expect(app.handwritingProfile.isComplete, isTrue);
    expect(find.byKey(const ValueKey('handwriting-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('handwriting-save-next')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'additional character returns to the typed text and removal locks setup',
      (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    app.saveHandwritingProfile(completedProfile());
    app.cancelPendingSave();
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: HandwritingDialog(app: app))));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('handwriting-text')), 'é');
    await settle(t);
    expect(
        t
            .widget<FilledButton>(
                find.byKey(const ValueKey('handwriting-insert')))
            .onPressed,
        isNull);
    await t.tap(find.widgetWithText(ActionChip, 'é'));
    await settle(t);
    final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final pen =
        await t.startGesture(rect.center, kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(20, 20));
    await pen.up();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('handwriting-save-next')));
    await settle(t);
    expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('handwriting-text')))
            .controller!
            .text,
        'é');
    expect(
        t
            .widget<FilledButton>(
                find.byKey(const ValueKey('handwriting-insert')))
            .onPressed,
        isNotNull);
    await t.tap(find.text('Edit handwriting'));
    await settle(t);
    expect(find.byKey(const ValueKey('handwriting-tile-a')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await t.tap(find.byKey(const ValueKey('handwriting-tile-a')));
    await settle(t);
    await t.ensureVisible(
        find.byKey(const ValueKey('handwriting-delete-variant')));
    await t.tap(find.byKey(const ValueKey('handwriting-delete-variant')));
    await settle(t);
    expect(app.handwritingProfile.isComplete, isFalse);
    expect(find.text('Back to text'), findsNothing);
    expect(find.byKey(const ValueKey('handwriting-insert')), findsNothing);
    expect(find.byKey(const ValueKey('handwriting-save-next')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('handwriting-back-overview')));
    await settle(t);
    expect(find.text('Continue setup'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets(
        'character overview and five variants fit narrow ${dark ? 'dark' : 'light'} window',
        (t) async {
      activeTester = t;
      if (!sqlite) return markTestSkipped('sqlite unavailable');
      t.view.physicalSize = const Size(400, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final profile = completedProfile();
      for (var i = 0; i < 4; i++) {
        profile.addSample('a', [sample(30.0 + i * 12)]);
      }
      app.saveHandwritingProfile(profile);
      app.cancelPendingSave();
      final boundaryKey = GlobalKey();
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(dark ? Brightness.dark : Brightness.light),
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(400, 760), textScaler: TextScaler.linear(1.3)),
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: Scaffold(body: HandwritingDialog(app: app))))));
      await settle(t);
      await t.tap(find.text('Schrift bearbeiten'));
      await settle(t);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('handwriting-tile-a')));
      await settle(t);
      expect(t.takeException(), isNull);
      await shot(t, boundaryKey, 'handwriting-edit-${dark ? 'dark' : 'light'}');
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('handwriting-variant-$i')), findsOneWidget);
      }
      await t
          .ensureVisible(find.byKey(const ValueKey('handwriting-variant-4')));
      await t.tap(find.byKey(const ValueKey('handwriting-variant-4')));
      await settle(t);
      expect(
          t
              .state<HandwritingPadState>(find.byType(HandwritingPad))
              .strokes
              .single
              .x
              .first,
          66);
      final save =
          t.getRect(find.byKey(const ValueKey('handwriting-save-next')));
      expect(save.bottom, lessThanOrEqualTo(760));
      expect(save.height, greaterThanOrEqualTo(52));
      expect(t.getCenter(find.byKey(const ValueKey('handwriting-pad'))).dy,
          lessThan(save.top));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
        'beta dialog fits narrow ${dark ? 'dark' : 'light'} window with large text',
        (t) async {
      activeTester = t;
      if (!sqlite) return markTestSkipped('sqlite unavailable');
      t.view.physicalSize = const Size(400, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(dark ? Brightness.dark : Brightness.light),
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(400, 760), textScaler: TextScaler.linear(1.3)),
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: Scaffold(body: HandwritingDialog(app: app))))));
      await settle(t);
      expect(t.takeException(), isNull);
      if (Platform.environment['OPENOTE_BETA_SHOTS'] == '1') {
        await t.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/handwriting-beta-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      // The polished setup fits at 760 px. A shorter window must still scroll
      // with fingers while keeping upward stylus strokes on the writing pad.
      t.view.physicalSize = const Size(400, 600);
      await t.pump();
      final scroll = t.state<ScrollableState>(find
          .descendant(
              of: find.byType(HandwritingDialog),
              matching: find.byType(Scrollable))
          .first);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final before = scroll.position.pixels;
      final padRect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
      final pen = await t.startGesture(padRect.center + const Offset(0, 40),
          kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(0, -30));
      await pen.moveBy(const Offset(0, -30));
      await pen.moveBy(const Offset(0, -30));
      await pen.up();
      await t.pump();
      expect(scroll.position.pixels, before,
          reason: 'writing must not scroll the pad');
      await t.drag(
          find.byKey(const ValueKey('handwriting-pad')), const Offset(0, -80));
      await settle(t);
      expect(scroll.position.pixels, greaterThan(before),
          reason: 'fingers still scroll');
      expect(find.byKey(const ValueKey('handwriting-text')), findsNothing);
      final confirm =
          t.getRect(find.byKey(const ValueKey('handwriting-save-next')));
      expect(confirm.bottom, lessThanOrEqualTo(600));
      expect(confirm.top, greaterThan(0));
      expect(t.takeException(), isNull);
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('generated lines fit A5 paper even at the largest letter size',
      (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    app.pageProps = PageProps(layout: 'paged', paperSize: 'A5');
    app.saveHandwritingProfile(completedProfile());
    app.cancelPendingSave();
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: HandwritingDialog(app: app))));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('handwriting-text')),
        List.filled(50, 'a').join());
    await settle(t);
    await t.ensureVisible(find.text('Size & spacing'));
    await t.tap(find.text('Size & spacing'));
    await settle(t);
    t.widget<Slider>(find.byType(Slider).at(0)).onChanged!(60);
    await t.pump();
    final width = t.widget<Slider>(find.byType(Slider).at(1));
    expect(width.max, PaperSize.a5.width - AppState.sheetMargin * 2);
    width.onChanged!(width.max);
    await t.pump();
    final insert = find.byKey(const ValueKey('handwriting-insert'));
    await t.ensureVisible(insert);
    await t.tap(insert);
    await settle(t);
    final block = app.blocks.singleWhere((b) => b.type == BlockType.ink);
    for (final raw in block.content['strokes'] as List) {
      final stroke = Stroke.fromJson(Map<String, dynamic>.from(raw as Map));
      expect(stroke.bounds().maxX,
          lessThanOrEqualTo(PaperSize.a5.width - AppState.sheetMargin));
      expect(stroke.bounds().maxX, lessThanOrEqualTo(block.x + block.w));
    }
    await t.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets(
        'conversion fits narrow ${dark ? 'dark' : 'light'} window and keeps insertion visible',
        (t) async {
      activeTester = t;
      if (!sqlite) return markTestSkipped('sqlite unavailable');
      t.view.physicalSize = const Size(400, 760);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      app.saveHandwritingProfile(completedProfile());
      app.cancelPendingSave();
      final boundaryKey = GlobalKey();
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(dark ? Brightness.dark : Brightness.light),
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(400, 760),
                  textScaler: TextScaler.linear(1.3),
                  disableAnimations: true),
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: Scaffold(body: HandwritingDialog(app: app))))));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('handwriting-text')), findsOneWidget);
      final insert = find.byKey(const ValueKey('handwriting-insert'));
      final before = t.getRect(insert);
      expect(before.bottom, lessThanOrEqualTo(760));
      await t.enterText(
          find.byKey(const ValueKey('handwriting-text')), 'Hallo Welt');
      await settle(t);
      if (Platform.environment['OPENOTE_BETA_SHOTS'] == '1') {
        await t.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  'build/handwriting-conversion-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.ensureVisible(find.text('Größe & Abstände'));
      await t.tap(find.text('Größe & Abstände'));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(t.getRect(insert), before);
      expect(t.widget<FilledButton>(insert).onPressed, isNotNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('lasso selection uses toolbar colour and thickness', (t) async {
    activeTester = t;
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    app.setTool(Tool.lasso);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
                listenable: app,
                builder: (_, __) => Column(children: [
                      CommandBar(app: app, drawOnly: true),
                      Expanded(child: PageCanvas(state: app)),
                    ])))));
    await settle(t);
    final canvas = t.getTopLeft(find.byType(PageCanvas));
    final at = app.canvas.screenToPage(const Offset(200, 240));
    app.insertHandwriting([
      Stroke(
          tool: 'pen',
          colorHex: '#000000',
          size: 2,
          x: [at.dx, at.dx + 40],
          y: [at.dy, at.dy],
          p: [.5, .5])
    ]);
    app.select(null);
    await t.pump();
    final mouse = await t.startGesture(canvas + const Offset(170, 210),
        kind: PointerDeviceKind.mouse);
    for (final point in [
      const Offset(270, 210),
      const Offset(270, 280),
      const Offset(170, 280),
      const Offset(170, 210)
    ]) {
      await mouse.moveTo(canvas + point);
    }
    await mouse.up();
    await settle(t);
    expect(app.hasInkSelection, isTrue);
    await t.tap(find.byKey(const ValueKey('ink-preset-2')));
    await t.pump();
    t.widget<Slider>(find.byKey(const ValueKey('ink-size'))).onChanged!(3);
    await t.pump();
    final selected =
        app.blocks.singleWhere((b) => app.selectedIds.contains(b.id));
    final stroke = Stroke.fromJson(Map<String, dynamic>.from(
        (selected.content['strokes'] as List).single as Map));
    expect(stroke.colorHex, isNot('#000000'));
    expect(stroke.size, 6);
    expect(app.tool, Tool.lasso);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });
}
