import 'dart:async';
import 'dart:ui' show AppExitType, AppExitResponse, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ui/windows_window_frame.dart';

class _ExitTestBinding extends AutomatedTestWidgetsFlutterBinding {
  AppExitType? requestedType;

  @override
  Future<AppExitResponse> exitApplication(AppExitType exitType,
      [int exitCode = 0]) {
    requestedType = exitType;
    // The standard test binding short-circuits here; simulate the engine's
    // callback to exercise the real AppLifecycleListener shutdown sequence.
    return handleRequestAppExit();
  }
}

void main() {
  final binding = _ExitTestBinding();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(WindowsWindowController.channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(
      WindowsWindowController.channel, null));

  Widget host(WindowsWindowController controller, {bool start = true}) =>
      MaterialApp(
        builder: (context, child) => WindowsWindowFrame(
            controller: controller, startMaximized: start, child: child!),
        home: const Scaffold(
            body: Column(children: [
          Align(alignment: Alignment.topRight, child: WindowsCaptionButtons()),
          Expanded(child: Center(child: Text('Notebook'))),
        ])),
      );

  testWidgets('starts maximized with permanent window buttons', (tester) async {
    final controller = WindowsWindowController(enabled: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'maximize'), hasLength(1));
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Close Openote'), findsOneWidget);
    await tester.tap(find.byTooltip('Minimize'));
    await tester.pump();
    expect(calls.last.method, 'minimize');
    await tester.tap(find.byTooltip('Maximize / restore'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'maximize'), hasLength(2));
    expect(find.byKey(const ValueKey('window-top-edge')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F11 uses the same maximize or restore action as the button',
      (tester) async {
    final controller = WindowsWindowController(enabled: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, start: false));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'maximize'), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pen hover never adds an overlay or hides the fixed controls',
      (tester) async {
    final controller = WindowsWindowController(enabled: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: const Offset(150, 80));
    await pen.moveTo(const Offset(150, 4));
    await tester.pump();
    expect(find.byTooltip('Close Openote'), findsOneWidget);
    expect(find.byKey(const ValueKey('window-top-edge')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byTooltip('Close Openote'), findsOneWidget);
    expect(find.text('Notebook'), findsOneWidget);
    await pen.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Linux has no overlay, window-channel calls or F11 handler',
      (tester) async {
    final controller = WindowsWindowController(enabled: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(calls, isEmpty);
    expect(find.byTooltip('Close Openote'), findsNothing);
    expect(find.byKey(const ValueKey('window-top-edge')), findsNothing);
    expect(find.text('Notebook'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('missing or failed native maximize bridge stays harmless', () async {
    final controller = WindowsWindowController(enabled: true);
    addTearDown(controller.dispose);
    messenger.setMockMethodCallHandler(WindowsWindowController.channel, null);
    await controller.maximize();
    messenger.setMockMethodCallHandler(WindowsWindowController.channel,
        (_) async => throw PlatformException(code: 'resize failed'));
    await controller.maximize();
    await controller.minimize();
  });

  test('close uses cancelable lifecycle exit, allowing shutdown to save',
      () async {
    final controller = WindowsWindowController(enabled: true);
    addTearDown(controller.dispose);
    final saved = Completer<void>();
    final lifecycle = AppLifecycleListener(onExitRequested: () async {
      await saved.future;
      return AppExitResponse.cancel;
    });
    addTearDown(lifecycle.dispose);
    var done = false;
    final closing = controller.close().then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.closing, true);
    expect(binding.requestedType, AppExitType.cancelable);
    expect(done, false);
    saved.complete();
    await closing;
    expect(controller.closing, false);
  });
}
