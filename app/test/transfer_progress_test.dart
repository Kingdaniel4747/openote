import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ui/transfer_progress.dart';

void main() {
  testWidgets(
      'a partially copied file advances percent without counting it as finished',
      (tester) async {
    final finish = Completer<void>();
    late TransferProgress progress;
    late Future<void> work;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () {
            work = runTransfer(context, 'Import files', (p) async {
              progress = p;
              p.update(done: 2, total: 4, current: .5, detail: 'third.pdf');
              await finish.future;
            });
          },
          child: const Text('Start')),
    ))));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('62% · 2 / 4 files · 2 remaining'), findsOneWidget);
    expect(find.text('third.pdf'), findsOneWidget);
    progress.update(done: 3, failed: 1);
    await tester.pump();
    expect(find.text('75% · 2 / 4 files · 1 remaining'), findsOneWidget);
    expect(find.text('1 failed'), findsOneWidget);
    finish.complete();
    await tester.pumpAndSettle();
    await work;
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed operation removes only its own progress dialog',
      (tester) async {
    final finish = Completer<void>();
    Object? error;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () async {
            try {
              await runTransfer(context, 'Export', (_) => finish.future);
            } catch (e) {
              error = e;
            }
          },
          child: const Text('Start')),
    ))));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    finish.completeError(StateError('disk full'));
    await tester.pumpAndSettle();
    expect(error, isA<StateError>());
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
