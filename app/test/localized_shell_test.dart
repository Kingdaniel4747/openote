import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/main.dart';
import 'package:openote/canvas/handwriting_spell_layer.dart';
import 'package:openote/editor/live_markdown_engine.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/spell/writing_services.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/windows_window_frame.dart';
import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() => expect(initSqliteForTests(), true));
  late Directory dir;
  late Repository repo;
  late AppState app;
  late List<MethodCall> calls;
  setUp(() async {
    AppState.syncLogEnabled = false;
    dir = Directory.systemTemp.createTempSync('openote-localized-shell-');
    repo = await Repository.openAt(dir);
    final nb = await repo.createNotebook('School');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.markOnboardingSeen();
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    app.setInterfaceLanguage('de');
    app.setWritingLanguage('de-DE');
    await repo.flushWorkspace();
    app.cancelPendingSave();
    calls = [];
    messenger.setMockMethodCallHandler(WindowsWindowController.channel,
        (call) async {
      calls.add(call);
      if (call.method == 'customChrome') return true;
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(WritingServices.channel, null);
    messenger.setMockMethodCallHandler(WindowsWindowController.channel, null);
    app.cancelPendingSave();
    await repo.flushWorkspace();
    app.dispose();
    repo.dispose();
    for (var attempt = 0;; attempt++) {
      try {
        await dir.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    AppState.syncLogEnabled = true;
  });

  testWidgets(
      'German shell keeps utilities in one titlebar above the four tabs',
      (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(OpenoteApp(app: app));
    await t.pumpAndSettle();
    expect(find.text('Zeichnen'), findsOneWidget);
    expect(find.text('Ansicht'), findsOneWidget);
    expect(find.byTooltip('Einstellungen…'), findsOneWidget);
    if (Platform.isWindows) {
      expect(find.byTooltip('Openote schließen'), findsOneWidget);
      expect(t.getCenter(find.byTooltip('Einstellungen…')).dy,
          lessThan(t.getCenter(find.text('Zeichnen')).dy));
      expect(find.byType(CommandBar), findsNWidgets(2));
      expect(calls.any((c) => c.method == 'chromeColor'), true);
    }
    await t.tap(find.byTooltip('Einstellungen…'));
    await t.pumpAndSettle();
    expect(find.text('Sprache der Oberfläche'), findsOneWidget);
    expect(find.text('Schreibsprache'), findsOneWidget);
    expect(repo.getSetting('interfaceLanguage'), 'de');
    expect(repo.getSetting('writingLanguage'), 'de-DE');
    await t.tap(find.byType(DropdownButton<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('English').last);
    await t.pump();
    app.cancelPendingSave();
    await t.pumpAndSettle();
    expect(find.text('Interface language'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(repo.getSetting('interfaceLanguage'), 'en');
    expect(t.takeException(), null);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('German typed text is underlined without automatic replacement', (t) async {
    app.spellCheckEnabled = true;
    final requests = <MethodCall>[];
    messenger.setMockMethodCallHandler(WritingServices.channel, (call) async {
      requests.add(call);
      if (call.method == 'start') {
        return 10;
      }
      return call.method == 'poll' ? [{'start': 4, 'length': 5}] : null;
    });
    final session = const LiveMarkdownEngine().openSession(
        block: Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'Ein Feler'}),
        app: app, onChanged: (_) {});
    await t.pump(const Duration(milliseconds: 60));
    await t.pump(const Duration(milliseconds: 120));
    final controller = session.commandController! as LiveMarkdownController;
    expect(requests.first.arguments['language'], 'de-DE');
    expect(requests.first.arguments['text'], 'Ein Feler');
    expect(app.writingServiceProblem, null, reason: requests.map((c) => '${c.method}: ${c.arguments}').join('\n'));
    expect(controller.misspellings, [const TextRange(start: 4, end: 9)]);
    expect(controller.text, 'Ein Feler');
    session.dispose();
  }, skip: !Platform.isWindows);

  testWidgets('handwriting checking waits for idle and paints an underline', (t) async {
    app.spellCheckEnabled = true;
    final stroke = Stroke(tool: 'pen', colorHex: '#000000', size: 2)
      ..x.addAll([20, 35])..y.addAll([20, 20]);
    app.blocks = [Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': [stroke.toJson()]})];
    var jobs = 0;
    messenger.setMockMethodCallHandler(WritingServices.channel, (call) async {
      if (call.method == 'start') { jobs++; return 11; }
      return call.method == 'poll'
          ? [{'text': 'Feler', 'x': 20, 'y': 10, 'w': 30, 'h': 20}] : null;
    });
    await t.pumpWidget(MaterialApp(home: SizedBox(width: 200, height: 200,
        child: HandwritingSpellLayer(app: app))));
    await t.pump(const Duration(milliseconds: 1000));
    expect(jobs, 0);
    await t.pump(const Duration(milliseconds: 250));
    await t.pump();
    expect(jobs, 1);
    final painter = t.widget<CustomPaint>(find.descendant(
        of: find.byType(HandwritingSpellLayer), matching: find.byType(CustomPaint))).painter!;
    expect((Canvas canvas) => painter.paint(canvas, const Size(200, 200)),
        paints..path(color: const Color(0xFFE53935), strokeWidth: 1.5));
    await t.pumpWidget(const SizedBox());
  }, skip: !Platform.isWindows);

  testWidgets('saving overlay explains close and blocks editing', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(OpenoteApp(app: app, closing: true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Wird gespeichert und geschlossen…'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });
}
