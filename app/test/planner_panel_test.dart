// The Planner panel at the widget level.
//
// The state layer is covered in `planner_state_test.dart`; this is the half
// that only fails on screen. The precedent is the command bar, where both bugs
// that shipped were *layout* failures invisible to every state test and to
// reading the code — and this panel packs an agenda, a month grid, a catch-up
// banner and a footer into a fixed 320px column.
//
// What is asserted is what the student reads: that a date they set appears
// without them navigating to the thing it belongs to (which is the entire
// complaint this feature answers), that overdue work is not quietly hidden,
// that a calendar row does not offer an edit that cannot work, and that none of
// it overflows a small window.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/study_stats.dart';
import 'package:openote/ui/planner_panel.dart';
import 'package:openote/ui/alert_popup.dart';
import 'package:openote/ui/planner_entry_editor.dart';
import 'package:openote/ui/planner_format.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A notebook with one section and a page of two to-do lines.
  Future<(AppState, String)> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    late String section;
    final tmp = Directory.systemTemp.createTempSync('onote_plannerpanel_');
    addTearDown(() {
      app.cancelPendingSave();
      app.dispose();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Planner');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      final page = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section,
              title: 'Week 3',
              position: 'a001'));
      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'Finish tutorial 4\nDraft the report'});
      NoteTag.writeInto(b.content, [
        NoteTag(kind: TagKind.todo, line: 0, checked: false),
        NoteTag(kind: TagKind.todo, line: 1, checked: false),
      ]);
      app.importPage(nb.id, page.id, [b], PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    return (app, section);
  }

  /// The panel as `AppShell` mounts it: a fixed-width column in a real window.
  Widget host(AppState app, {double height = 720}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: height,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Row(children: [PlannerPanel(app: app)]),
            ),
          ),
        ),
      );

  /// Past both debounces, twice, because they **chain**: `markDirty` schedules
  /// a 700ms autosave, and the save then calls `_persistSession`, which
  /// schedules the repository's own 400ms workspace write. One pump clears the
  /// first and leaves the second pending — which the framework treats as a
  /// leak, correctly.
  ///
  /// `pumpAndSettle` cannot do this on its own: it does not advance the clock
  /// when no frame is scheduled, and neither timer schedules one.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
    }
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 15 && finder.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    expect(finder.hitTestable(), findsOneWidget);
  }

  Future<void> selectCategory(WidgetTester tester, String category) async {
    final selector = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find
        .text(category == 'to-do'
            ? 'To-do'
            : category == 'exam'
                ? 'Exam'
                : 'Homework')
        .last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'quick homework, full notes, color and completion share one entry',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();
    final day = DateUtils.dateOnly(DateTime.now());
    final dayCell =
        find.byKey(ValueKey('planner-day-${day.year}-${day.month}-${day.day}'));
    await tester.tap(dayCell);
    await tester.pumpAndSettle();
    const notes =
        'Read the whole chapter.\nThen solve exercises 1–15.\nExplain every step and bring your notes to class.';
    await tester.enterText(
        find.byKey(const ValueKey('planner-entry-title')), 'Maths homework');
    await tester.enterText(
        find.byKey(const ValueKey('planner-entry-notes')), notes);
    await reveal(tester, find.byKey(const ValueKey('planner-color-blue')));
    await tester.tap(find.byKey(const ValueKey('planner-color-blue')));
    await tester.tap(find.text('Save'));
    app.cancelPendingSave();
    await tester.pumpAndSettle();
    final entry = app.planner.reminders.all.single;
    expect(entry.category, 'homework');
    expect(entry.color, 'blue');
    expect(entry.pageId, isNull);
    expect(entry.allDay, isTrue);
    expect(entry.at, day);
    expect(find.textContaining(notes), findsNothing);
    expect(
        find.descendant(of: dayCell, matching: find.text('1')), findsOneWidget);
    await tester.tap(find.text('Maths homework'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('planner-entry-notes')))
            .controller!
            .text,
        notes);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(TimePickerDialog), findsNothing);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Done with this reminder'));
    app.cancelPendingSave();
    await tester.pumpAndSettle();
    expect(entry.dismissed, isTrue);
    expect(
        find.descendant(of: dayCell, matching: find.text('1')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('current month works without a selected day and keeps drafts',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final month = '${monthName(now.month)} ${now.year}';
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(month), findsNothing);
    await tester.tap(find.byTooltip('Current month'));
    await tester.pumpAndSettle();
    expect(find.text(month), findsOneWidget);
    final cell =
        find.byKey(ValueKey('planner-day-${now.year}-${now.month}-${now.day}'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('planner-entry-title')), 'Unfinished draft');
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('planner-entry-title')))
            .controller!
            .text,
        'Unfinished draft');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    app.cancelPendingSave();
    await tester.pumpAndSettle();
    expect(app.planner.reminders.all.single.text, 'Unfinished draft');
    await tester.pumpWidget(const SizedBox());
    app.cancelPendingSave();
    app.dispose();
  });

  for (final category in ['to-do', 'homework', 'exam']) {
    testWidgets('calendar creates and edits an all-day $category',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app, _) = await newApp(tester);
      final originalNotebook = app.notebookId!;
      late String otherNotebook;
      await tester.runAsync(() async {
        await app.createNotebook('Another notebook');
        otherNotebook = app.notebookId!;
        await app.selectNotebook(originalNotebook);
      });
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add entry'), findsNothing);
      final today = DateUtils.dateOnly(DateTime.now());
      await tester.tap(find.text('${today.day}').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await selectCategory(tester, category);
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Mathematics');
      await tester.enterText(
          find.byType(TextField).last, 'Private description');
      await reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);
      final entry = app.planner.reminders.all.single;
      expect(entry.category, category == 'to-do' ? 'todo' : category);
      expect(entry.at, today);
      expect(entry.allDay, isTrue);
      expect(app.planner.agenda().single.allDay, isTrue);
      expect(entry.toJson()['at'], dayKey(today));
      expect(
          find.descendant(
              of: find.byType(ListView), matching: find.text('Mathematics')),
          findsOneWidget);
      expect(find.textContaining('Private description'), findsNothing);
      final notebook = entry.notebookId;
      final page = entry.pageId;
      await tester.runAsync(() => app.selectNotebook(otherNotebook));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(ListView), matching: find.text('Mathematics')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          'Private description');
      await tester.enterText(find.byType(TextField).first, 'Updated title');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(entry.notebookId, notebook);
      expect(entry.pageId, page);
      expect(entry.at, today);
      await tester.runAsync(() => app.openPlannerTarget(
          targetNotebookId: entry.notebookId, targetPageId: entry.pageId));
      expect(app.notebookId, notebook);
      expect(app.pageId, page);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      app.cancelPendingSave();
      app.dispose();
    });
  }
  testWidgets('planner resolves notebook, section and page by IDs',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    final notebook = app.notebookId!;
    final page = app.pageId!;
    app.renameNode(section, 'Same section');
    app.renameNode(page, 'Same page');
    await tester.runAsync(() async {
      await app.createNotebook('Other Planner');
      app.renameNode(app.activeSectionId!, 'Same section');
      app.renameNode(app.pageId!, 'Same page');
    });
    final otherNotebook = app.notebookId;
    app.planner.reminders.add(
        text: 'Go to original',
        at: DateTime.now(),
        notebookId: notebook,
        pageId: page);
    await tester.pumpWidget(host(app));
    await settle(tester);
    expect(find.text('Same page'), findsNothing);
    await tester.tap(find.text('Go to original'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Open linked page'));
    await tester.runAsync(() => tester.tap(find.text('Open linked page')));
    await settle(tester);
    expect(app.notebookId, notebook);
    expect(app.activeSectionId, section);
    expect(app.pageId, page);
    await tester.runAsync(() async {
      await app.selectNotebook(otherNotebook!);
      // Legacy entries with no notebook ID resolve only a unique page ID.
      expect(await app.openPlannerTarget(targetPageId: page), isNull);
    });
    expect(app.pageId, page);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    app.planner.reminders.add(
        text: 'Deleted target',
        at: DateTime.now(),
        notebookId: notebook,
        pageId: 'missing-page');
    await settle(tester);
    await tester.tap(find.text('Deleted target'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Open linked page'));
    await tester.tap(find.text('Open linked page'));
    await settle(tester);
    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(app.pageId, page);
    await tester.runAsync(() async {
      expect(
          await app.openPlannerTarget(
              targetNotebookId: 'missing-notebook', targetPageId: page),
          isNotNull);
    });
    expect(app.notebookId, notebook);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    app.cancelPendingSave();
    app.dispose();
  });

  testWidgets('all-day alerts have a date and no time or snooze picker',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    final day = DateUtils.dateOnly(DateTime.now());
    app.planner.reminders.add(text: 'All-day exam', at: day, allDay: true);
    app.planner.startScheduler();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Stack(children: [AlertPopup(app: app)]))));
    await settle(tester);
    expect(find.text('All-day exam'), findsOneWidget);
    expect(find.text('Snooze'), findsNothing);
    expect(find.textContaining('00:00'), findsNothing);
    expect(find.textContaining('Was due at'), findsNothing);
    await tester.tap(find.text('Done'));
    expect(app.planner.reminders.all.single.dismissed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    app.cancelPendingSave();
    app.dispose();
  });

  testWidgets('legacy undated entries remain editable and completable',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    app.planner.addUndatedEntry('Buy paper — Keep this description',
        category: 'homework');
    await tester.pumpWidget(host(app));
    await settle(tester);
    expect(find.text('Buy paper'), findsOneWidget);
    expect(find.textContaining('Keep this description'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    expect(app.planner.undatedEntries.single.done, isTrue);
    await tester.tap(find.text('Buy paper'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Keep this description');
    await tester.enterText(find.byType(TextField).first, 'Buy notebooks');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(app.planner.undatedEntries.single.text,
        'Buy notebooks — Keep this description');
    expect(app.planner.undatedEntries.single.category, 'homework');
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(app.planner.undatedEntries, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    app.cancelPendingSave();
    app.dispose();
  });

  testWidgets('an empty planner offers actions from a calendar day',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    expect(find.text('PLANNER'), findsOneWidget);
    expect(find.text('Nothing dated yet.'), findsNothing);
    await tester.tap(find.text('${DateTime.now().day}').first);
    await tester.pumpAndSettle();
    expect(find.byType(PlannerEntryEditor), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.textContaining('Subscribe'), findsNothing);
  });

  testWidgets('an exam date is visible without opening the section it is on',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    final title = app.nodes.firstWhere((n) => n.id == section).title;
    app.study
        .setExamDate(section, DateTime.now().add(const Duration(days: 14)));
    await settle(tester);

    // This is the whole complaint: before the planner, that date could only be
    // read from inside the study panel, on the section you happened to be on.
    expect(find.text(title), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text(title)), buttons: 2);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Pick a date…'), findsNothing);
  });

  testWidgets('an occupied day shows its entries and the inline editor',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    final now = DateTime.now();
    app.planner.reminders
        .add(text: 'Biology', at: DateTime(now.year, now.month, now.day, 17));
    await tester.pumpWidget(host(app));
    await settle(tester);
    await tester.tap(find.text('${now.day}').first);
    await tester.pumpAndSettle();
    expect(find.text('Biology'), findsOneWidget);

    expect(find.byType(PlannerEntryEditor), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    app.cancelPendingSave();
    app.dispose(); // Stop the future reminder's scheduler before fake-async verification.
  });

  testWidgets('a title alone is enough for a new exam', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().day}').first);
    await tester.pumpAndSettle();
    await selectCategory(tester, 'exam');
    final dialogFields = find.descendant(
        of: find.byType(PlannerEntryEditor), matching: find.byType(TextField));
    await tester.enterText(dialogFields.at(1), 'Optional note');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull);
    await tester.enterText(dialogFields.at(1), '');
    await tester.enterText(dialogFields.first, 'Biology');
    expect(tester.widget<TextField>(dialogFields.first).controller!.text,
        'Biology');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(app.planner.reminders.all, hasLength(1));
    final exam = app.planner.reminders.all.single;
    expect(exam.text, 'Biology');
    expect(exam.category, 'exam');
  });

  testWidgets('a missed deadline leaves the active planner', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    app.setTagDue(app.blocks.single.id, 0, TagKind.todo, yesterday);
    await settle(tester);

    expect(find.text('Finish tutorial 4'), findsNothing);
  });

  testWidgets('ticking a task in the planner ticks it in the note',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    app.setTagDue(app.blocks.single.id, 0, TagKind.todo, DateTime.now());
    await settle(tester);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await settle(tester);

    // The agenda is a lens: there is one truth, and it is the tag.
    final tag = NoteTag.listFrom(app.blocks.single.content)
        .firstWhere((t) => t.line == 0);
    expect(tag.checked, isTrue);
  });

  testWidgets(
      'a calendar row says it is read-only rather than offering an edit',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    final tmp = Directory.systemTemp.createTempSync('onote_plannerics_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final start = DateTime.now().add(const Duration(days: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${start.year}${two(start.month)}${two(start.day)}T090000';
    final ics = File('${tmp.path}/t.ics')
      ..writeAsStringSync('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
          'UID:e1\r\nSUMMARY:Discrete Maths lecture\r\n'
          'DTSTART:$stamp\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n');
    await tester.runAsync(() => app.planner.subscribeCalendar(ics.path));
    await tester.pumpWidget(host(app));
    await settle(tester);

    final titles = find.text('Discrete Maths lecture');
    expect(titles, findsOneWidget);

    await tester.tapAt(tester.getCenter(titles), buttons: 2 /* secondary */);
    await tester.pumpAndSettle();
    expect(find.text('From your calendar — read-only'), findsOneWidget);
    expect(find.text('Clear the date'), findsNothing);

    await tester.tapAt(const Offset(700, 20)); // dismiss the menu
    await tester.pumpAndSettle();
  });

  testWidgets('the month grid marks days that have something on them',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    app.study.setExamDate(section, DateTime.now().add(const Duration(days: 3)));
    await tester.pumpWidget(host(app));
    await settle(tester);

    // The compact calendar is always open.
    expect(find.byTooltip('Show the month'), findsNothing);
    expect(find.byTooltip('Show the list'), findsNothing);
    expect(find.byTooltip('Next month'), findsOneWidget);
    // Monday-start weekday header.
    expect(find.text('W'), findsOneWidget);

    await tester.tap(find.text('${DateTime.now().day}').first);
    await tester.pumpAndSettle();
    expect(find.byType(PlannerEntryEditor), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  // A deadline visible only inside the planner would be a fact about a line
  // that the line itself does not show — so you would have to remember to go
  // and look, which is the failure the planner exists to fix.
  group('the deadline shows in the note too', () {
    Widget note(Map<int, List<NoteTag>> tags) => MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              text: 'Finish tutorial 4',
              baseStyle: const TextStyle(fontSize: 14),
              tagsByLine: tags,
            ),
          ),
        );

    testWidgets('a date this week reads as a weekday', (tester) async {
      final due = DateTime.now().add(const Duration(days: 3));
      await tester.pumpWidget(note({
        0: [
          NoteTag(kind: TagKind.todo, line: 0, checked: false, due: dayKey(due))
        ]
      }));
      await tester.pumpAndSettle();
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      expect(find.text(names[due.weekday - 1]), findsOneWidget);
    });

    testWidgets('an undated tag adds nothing to the gutter', (tester) async {
      await tester.pumpWidget(note({
        0: [NoteTag(kind: TagKind.todo, line: 0, checked: false)]
      }));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing); // the gutter uses an icon
      expect(find.text('today'), findsNothing);
      expect(find.text('tomorrow'), findsNothing);
    });

    testWidgets('an overdue one says so', (tester) async {
      final due = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(note({
        0: [NoteTag(kind: TagKind.todo, line: 0, due: dayKey(due))]
      }));
      await tester.pumpAndSettle();
      expect(find.text('yesterday'), findsOneWidget);
    });
  });

  testWidgets('it survives a short, narrow window without overflowing',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    tester.view.physicalSize = const Size(900, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    app.study.setExamDate(section, now.add(const Duration(days: 9)));
    app.setTagDue(app.blocks.single.id, 0, TagKind.todo,
        now.subtract(const Duration(days: 2)));
    app.setTagDue(app.blocks.single.id, 1, TagKind.todo, now);
    app.planner.reminders
        .add(text: 'Re-read the proof of 2.7', at: now, id: 'r1');

    await tester.pumpWidget(host(app, height: 560));
    await settle(tester);
    expect(tester.takeException(), isNull);

    expect(tester.takeException(), isNull);
  });
}
