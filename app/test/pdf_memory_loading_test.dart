import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
// Native ABI types from pdfrx_engine's pinned transitive dependency.
// ignore: depend_on_referenced_packages
import 'package:pdfium_dart/pdfium_dart.dart' as native;
import 'package:pdfrx/pdfrx.dart';
// Exercise the local native compatibility patch without loading PDFium.
// ignore: implementation_imports
import 'package:pdfrx_engine/src/native/pdfrx_pdfium.dart';
// ignore: implementation_imports
import 'package:pdfrx_engine/src/native/pdfium_file_access.dart';
// ignore: implementation_imports
import 'package:pdfrx_engine/src/native/worker.dart';

class _Document implements PdfDocument {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend extends PdfrxEntryFunctionsImpl {
  late FutureOr<int> Function(Uint8List, int, int) read;
  int? memoryLimit;
  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List, int, int) read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) async {
    this.read = read;
    memoryLimit = maxSizeToCacheOnMemory;
    return _Document();
  }
}

void main() {
  for (final size in [1024, (1 << 20) + 1, 4 << 20]) {
    test('in-memory PDF of $size bytes avoids native read callbacks', () async {
      final backend = _Backend();
      final source = Uint8List(size)..[size - 1] = 123;
      await backend.openData(source, sourceName: 'worksheet.pdf');
      expect(backend.memoryLimit, size);
      final tail = Uint8List(4);
      expect(await backend.read(tail, size - 4, 4), 4);
      expect(tail, [0, 0, 0, 123]);
    });
  }

  test('Windows native reader completes fast, delayed and failed reads',
      () async {
    var calls = 0;
    final access =
        await PdfiumFileAccess.create(512, (buffer, position, size) async {
      calls++;
      if (position == 511) throw StateError('read failed');
      if (position.isOdd) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      buffer[0] = position % 256;
      return size;
    });
    try {
      final results = await BackgroundWorker.compute((address) {
        final access = Pointer<native.FPDF_FILEACCESS>.fromAddress(address);
        final read = access.ref.m_GetBlock.asFunction<
            int Function(Pointer<Void>, int, Pointer<UnsignedChar>, int)>();
        final buffer = malloc<UnsignedChar>(1);
        try {
          final results = <int>[];
          for (var i = 0; i < 512; i++) {
            results.add(read(access.ref.m_Param, i, buffer, 1));
            if (i != 511 && buffer.value != i % 256) {
              throw StateError('Incorrect read at $i');
            }
          }
          return results;
        } finally {
          malloc.free(buffer);
        }
      }, access.fileAccess)
          .timeout(const Duration(seconds: 15));
      expect(calls, 512);
      expect(results.take(511), everyElement(1));
      expect(results.last, -1);
    } finally {
      access.dispose();
      await BackgroundWorker.stop();
    }
  }, skip: !Platform.isWindows);
}
