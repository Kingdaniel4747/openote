import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
// Exercise the patched native cache without starting PDFium's worker isolate.
// ignore: implementation_imports
import 'package:pdfrx_engine/src/native/pdf_file_cache.dart';

class _Document implements PdfDocument {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements PdfrxEntryFunctions {
  final document = _Document();
  late FutureOr<int> Function(Uint8List, int, int) read;
  late int fileSize;
  void Function()? disposeCache;

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
    this.fileSize = fileSize;
    disposeCache = onDispose;
    return document;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final supplied in [false, true]) {
    test('range cache reads across await boundaries (supplied=$supplied)',
        () async {
      final dir = await Directory.systemTemp.createTemp('openote-pdf-range-');
      final oldDirectory = Pdfrx.getCacheDirectory;
      Pdfrx.getCacheDirectory = () => dir.path;
      final data = List<int>.generate(24, (i) => i);
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader)!;
        requests.add(range);
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final start = int.parse(match[1]!);
        final end = int.parse(match[2]!).clamp(0, data.length - 1);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader,
              'bytes $start-$end/${data.length}')
          ..add(data.sublist(start, end + 1));
        await request.response.close();
      });
      final uri = Uri.parse('http://127.0.0.1:${server.port}/test.pdf');
      final cache = supplied
          ? await PdfFileCache.fromFile(File('${dir.path}/supplied.cache'))
          : await PdfFileCache.fromUri(uri);
      final backend = _Backend();
      try {
        final doc = await pdfDocumentFromUri(uri,
            blockSize: 8,
            cache: supplied ? cache : null,
            entryFunctions: backend);
        expect(identical(doc, backend.document), isTrue);
        expect(backend.fileSize, data.length);
        final buffer = Uint8List(18);
        expect(await backend.read(buffer, 3, buffer.length), 18);
        expect(buffer, data.sublist(3, 21));
        expect(requests, ['bytes=0-7', 'bytes=8-15', 'bytes=16-23']);
        final again = Uint8List(18);
        expect(await backend.read(again, 3, again.length), 18);
        expect(again, buffer);
        expect(requests.length, 3, reason: 'cached blocks are reused');
      } finally {
        backend.disposeCache?.call();
        await cache.close();
        await serving.cancel();
        await server.close(force: true);
        Pdfrx.getCacheDirectory = oldDirectory;
        // onDispose closes asynchronously; allow its file handle to settle.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await dir.delete(recursive: true);
      }
    });
  }
}
