import 'dart:io' show exit;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_strings.dart';

import 'core/single_instance.dart';
import 'core/startup_args.dart';
import 'media/video_playback.dart';
import 'media/pdf_pages.dart';
import 'state/app_state.dart';
import 'store/repository.dart';
import 'theme/onote_theme.dart';
import 'ui/app_shell.dart';
import 'ui/windows_window_frame.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The notebook we were launched to open: `openote Physics.onotebook`, or a
  // double-click in the file manager — on the notebook folder itself where the
  // shell will open one, and on the `Open this notebook.onotelink` inside it
  // everywhere else (v0.17 Step 8b). Parsed before anything else because the
  // single-instance hand-off below needs to know what to hand over, and it
  // hands over a path whether that path is a file or a directory. See
  // core/startup_args.dart, and core/open_target.dart for which of the two it
  // turned out to be.
  final requested = notebookPathFromArgs(args);

  // BEFORE runApp, and this ordering is the whole point: if another Openote is
  // already running on this workspace it takes the notebook and we exit
  // without ever painting. A window that appears and immediately vanishes
  // would be worse than either outcome.
  //
  // The cost is that the first frame now waits on resolving the workspace
  // folder and one file lock — a `mkdir` and an `open` — which is a few
  // milliseconds against the "the app takes ages to appear" work below. There
  // is no way to know whether this process is allowed to exist without asking.
  SingleInstance? instance;
  var handedOver = false;
  try {
    final dir = await Repository.resolveWorkspaceDir();
    instance = await SingleInstance.claim(dir, openPath: requested);
    handedOver = instance == null;
  } catch (_) {
    // The workspace folder could not even be resolved. Say nothing here and
    // carry on: `Repository.open()` is about to fail the same way, and it
    // fails into the in-window error screen below instead of into a process
    // that dies with no window at all.
    instance = null;
  }
  // Outside the try on purpose. A null `instance` means "we handed over, stop"
  // on one path and "carry on without a claim" on the other, so the decision
  // is spelled with its own flag rather than left for a reader to infer.
  if (handedOver) exit(0);

  // pdfrx wires its own statics (asset loader, and the cache directory pdfium
  // needs for its font cache) inside this call. Its *widgets* do it implicitly
  // in initState, but Openote drives the document API directly and never
  // builds one — so without this, opening a PDF throws
  // "Pdfrx.getCacheDirectory is not set" before pdfium is even touched.
  // Must run on the root isolate, before any PDF work.
  // PDF initialization is awaited lazily by PdfRuntime, with error handling.
  // Resolve libmpv once, here, rather than the first time a block tries to
  // play something: on a Linux box without it, `MediaKit.ensureInitialized`
  // throws, and a throw inside a widget build is a red screen where a "you
  // need to install mpv-libs" card belongs. See media/video_playback.dart.
  // Awaited: on Windows this also resolves whether the downloaded engine is
  // present, and a page that renders its video cards before that answer is
  // known shows "needs the video player" to somebody who already has it.
  // Probe behind the first splash frame, not before runApp.
  // Paint a window IMMEDIATELY; open the workspace behind it. Blocking runApp
  // on Repository.open + init left the window invisible until SQLite and the
  // restored page were fully loaded ("the app takes ages to appear").
  runApp(OpenoteBoot(notebookPath: requested, instance: instance));
}

/// Boots the workspace behind a lightweight splash, then swaps in the app.
/// Never fails invisibly: a startup error renders in-window (PLAT-9 in
/// spirit) instead of leaving a ghost process.
class OpenoteBoot extends StatefulWidget {
  const OpenoteBoot({super.key, this.notebookPath, this.instance});

  /// The notebook named on the command line, absolute — or null.
  final String? notebookPath;

  /// Our claim on this workspace, when we got one. Held here so it lives as
  /// long as the app and is released on the way out.
  final SingleInstance? instance;

  @override
  State<OpenoteBoot> createState() => _OpenoteBootState();
}

class _OpenoteBootState extends State<OpenoteBoot> {
  AppState? _app;
  (Object, StackTrace)? _error;
  AppLifecycleListener? _lifecycle;
  bool _closing = false;
  bool _closeFailed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      await VideoPlayback.probe();
      final repo = await Repository.open();
      final app = AppState(repo);
      await app.init(notebookPath: widget.notebookPath);
      // Every LATER double-click arrives here, as a request file the new
      // process left behind before exiting. See core/single_instance.dart.
      widget.instance?.listen(app.openNotebookFile);
      // Persist before the process goes away. Autosave is debounced, so without
      // this the last edits before a window close were silently lost — and the
      // SQLite handles never got a clean close (no WAL checkpoint).
      _lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          if (_closing) return AppExitResponse.cancel;
          if (mounted)
            setState(() {
              _closing = true;
              _closeFailed = false;
            });
          await WidgetsBinding.instance.endOfFrame;
          // The save remains fully awaited, but the Windows window can leave
          // the screen at once. If anything cannot be saved it is restored
          // below with the existing recovery message.
          await WindowsWindowController.hideForExit();
          try {
            await app.shutdown();
            // A page render may otherwise keep pdfium and its worker alive for
            // up to its 30-second timeout after the window has been closed.
            // Cancel first, then give cleanup a short bounded opportunity.
            await PdfPages.reset()
                .timeout(const Duration(milliseconds: 150), onTimeout: () {});
            if (app.hasUnsavedChanges) {
              await WindowsWindowController.restoreAfterFailedExit();
              if (mounted)
                setState(() {
                  _closing = false;
                  _closeFailed = true;
                });
              return AppExitResponse.cancel;
            }
            await widget.instance?.dispose();
            return AppExitResponse.exit;
          } catch (_) {
            await WindowsWindowController.restoreAfterFailedExit();
            if (mounted)
              setState(() {
                _closing = false;
                _closeFailed = true;
              });
            return AppExitResponse.cancel;
          }
        },
      );
      if (mounted) setState(() => _app = app);
    } catch (e, st) {
      if (mounted) setState(() => _error = (e, st));
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    // Stops the request poll. The lock itself is released by the OS when the
    // process goes, so this is about not leaving a timer behind in a hot
    // reload rather than about correctness on exit.
    widget.instance?.dispose();
    _app?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err != null) return _StartupError(error: err.$1, stack: err.$2);
    final app = _app;
    if (app != null)
      return OpenoteApp(
          app: app,
          closing: _closing,
          closeFailed: _closeFailed,
          dismissCloseError: () => setState(() => _closeFailed = false));
    return MaterialApp(
      title: 'Openote',
      debugShowCheckedModeBanner: false,
      theme: onoteTheme(Brightness.light),
      darkTheme: onoteTheme(Brightness.dark),
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 42),
              SizedBox(height: 14),
              AppText('Opening Openote…'),
              SizedBox(height: 14),
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.stack});
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Openote',
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Openote couldn't start",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text(
                      'Something failed while opening your workspace. Your notes '
                      'are not affected. Details below — please report this.'),
                  const SizedBox(height: 16),
                  SelectableText('$error\n\n$stack',
                      style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontFamilyFallback: onoteFontFallback,
                          fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpenoteApp extends StatefulWidget {
  const OpenoteApp(
      {super.key,
      required this.app,
      this.closing = false,
      this.closeFailed = false,
      this.dismissCloseError});
  final AppState app;
  final bool closing;
  final bool closeFailed;
  final VoidCallback? dismissCloseError;

  @override
  State<OpenoteApp> createState() => _OpenoteAppState();
}

class _OpenoteAppState extends State<OpenoteApp> {
  ThemeMode? _builtMode;
  String? _builtLanguage;
  bool? _builtClosing;
  bool? _builtCloseFailed;
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        // Rebuild the root MaterialApp ONLY when the theme mode changes.
        // Content updates ride AppShell's own listener — rebuilding the whole
        // tree from the root on every notify (each keystroke, drag frame)
        // doubled per-frame build work.
        if (_built != null &&
            _builtMode == widget.app.themeMode &&
            _builtLanguage == widget.app.interfaceLanguage &&
            _builtClosing == widget.closing &&
            _builtCloseFailed == widget.closeFailed) {
          return _built!;
        }
        _builtMode = widget.app.themeMode;
        _builtLanguage = widget.app.interfaceLanguage;
        _builtClosing = widget.closing;
        _builtCloseFailed = widget.closeFailed;
        return _built = MaterialApp(
          title: 'Openote',
          debugShowCheckedModeBanner: false,
          theme: onoteTheme(Brightness.light),
          darkTheme: onoteTheme(Brightness.dark),
          themeMode: widget.app.themeMode, // Settings: Auto / Light / Dark
          locale: Locale(widget.app.interfaceLanguage),
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => WindowsWindowFrame(
            startMaximized: widget.app.startMaximized,
            child: Stack(children: [
              child ?? const SizedBox.shrink(),
              if (widget.closing) ...[
                const ModalBarrier(dismissible: false, color: Colors.black38),
                const Center(
                    child: AlertDialog(
                  title: AppText('Saving and closing…'),
                  content: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator()),
                    SizedBox(width: 18),
                    Flexible(
                        child: AppText(
                            'Please wait. Your notes are being saved.')),
                  ]),
                )),
              ],
              if (widget.closeFailed) ...[
                const ModalBarrier(dismissible: false, color: Colors.black38),
                Center(
                    child: AlertDialog(
                  title: const AppText('Saving failed'),
                  content: const AppText(
                      'Could not finish saving. Openote has stayed open. Check the save warning and try again.'),
                  actions: [
                    TextButton(
                        onPressed: widget.dismissCloseError,
                        child: const AppText('Close'))
                  ],
                )),
              ],
            ]),
          ),
          home: AppShell(app: widget.app),
        );
      },
    );
  }
}
