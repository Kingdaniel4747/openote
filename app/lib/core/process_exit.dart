import 'dart:ffi';
import 'dart:io';

/// Call only after pending edits have been saved and SQLite has been closed.
/// Dart's exit waits for isolates inside native calls. A stuck PDFium render
/// can therefore keep the process (and workspace lock) alive indefinitely.
Never exitSavedProcess(int code) {
  if (Platform.isWindows) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final currentProcess = kernel.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetCurrentProcess');
    final terminate = kernel.lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)>('TerminateProcess');
    if (terminate(currentProcess(), code) == 0) {
      throw StateError('Windows could not terminate the saved Openote process');
    }
  }
  exit(code);
}
