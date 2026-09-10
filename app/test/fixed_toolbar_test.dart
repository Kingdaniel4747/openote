import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ui/fixed_toolbar.dart';

void main() {
  Widget button(String label) =>
      TextButton(onPressed: () {}, child: Text(label));

  Future<void> pump(WidgetTester tester, double width) => tester.pumpWidget(
        MaterialApp(
            home: Scaffold(
                body: SizedBox(
          width: width,
          height: 40,
          child: FixedToolbar(children: [
            button('Picture'),
            button('PDF slides'),
            button('File')
          ]),
        ))),
      );

  testWidgets('keeps declaration order until the measured width runs out',
      (tester) async {
    await pump(tester, 120);
    await tester.pump();
    expect(find.text('Picture'), findsOneWidget);
    expect(find.byTooltip('More commands'), findsOneWidget);
    await tester.tap(find.byTooltip('More commands'));
    await tester.pumpAndSettle();
    expect(find.text('PDF slides'), findsWidgets);
    expect(find.text('File'), findsWidgets);
  });

  testWidgets('uses no overflow trigger when every command fits',
      (tester) async {
    await pump(tester, 700);
    await tester.pump();
    expect(find.text('Picture'), findsOneWidget);
    expect(find.text('PDF slides'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    // The render object removes the trigger from paint and hit testing when no
    // item folds. Its widget remains mounted so future resizes can measure it.
    expect(tester.getSize(find.byType(FixedToolbar)), const Size(700, 40));
  });
}
