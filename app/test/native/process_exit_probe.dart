import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:openote/core/process_exit.dart';

void blockedRender(SendPort ready) {
  final sleep = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Void Function(Uint32), void Function(int)>('Sleep');
  ready.send(null);
  sleep(60000);
}

Future<void> main(List<String> args) async {
  final lock = File('${args.single}.lock').openSync(mode: FileMode.append);
  lock.lockSync(FileLock.exclusive);
  final ready = ReceivePort();
  await Isolate.spawn(blockedRender, ready.sendPort);
  await ready.first;
  ready.close();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  File(args.single).writeAsStringSync('saved and closed', flush: true);
  exitSavedProcess(0);
}
