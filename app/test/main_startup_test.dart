import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/main.dart';

void main() {
  testWidgets('failed workspace claim stays on the startup error screen',
      (tester) async {
    await tester.pumpWidget(const OpenoteBoot(
        startupError: FileSystemException('Existing Openote did not respond')));
    await tester.pumpAndSettle();
    expect(find.text("Openote couldn't start"), findsOneWidget);
    expect(
        find.textContaining('Existing Openote did not respond'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
