import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/api/scanner_import.dart';
import 'package:openote/api/scanner_receiver.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  test('receiver accepts only its paired token and forwards image bytes',
      () async {
    Uint8List? received;
    final receiver = ScannerReceiver(
      onScan: (bytes, mime, filename) async {
        expect(mime, 'image/jpeg');
        expect(filename, 'page-1.jpg');
        received = bytes;
      },
    );
    await receiver.start();
    addTearDown(receiver.stop);

    Future<int> send(String token) async {
      final client = HttpClient();
      try {
        final request = await client.post(
          InternetAddress.loopbackIPv4.host,
          receiver.port!,
          '/v1/scan',
        );
        request.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
          ..contentType = ContentType('image', 'jpeg')
          ..set('x-openote-filename', 'page-1.jpg');
        request.add(const [1, 2, 3, 4]);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    expect(await send('wrong'), HttpStatus.unauthorized);
    expect(received, isNull);
    expect(await send(receiver.token), HttpStatus.created);
    expect(received, Uint8List.fromList(const [1, 2, 3, 4]));
  });

  test('a received scan is stored inside the selected notebook page', () async {
    if (!initSqliteForTests()) return markTestSkipped('sqlite unavailable');
    AppState.syncLogEnabled = false;
    final temporary = Directory.systemTemp.createTempSync('onote_phone_scan_');
    final repository = await Repository.openAt(temporary);
    final notebook = await repository.createNotebook('School');
    final app = AppState(repository)
      ..notebookId = notebook.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((node) => node.kind == NodeKind.page);

    try {
      final inserted = await importPhoneScan(
        app,
        notebookId: notebook.id,
        pageId: page.id,
        bytes: Uint8List.fromList(const [10, 20, 30]),
        mime: 'image/jpeg',
      );
      final stored = app.readPageOf(notebook.id, page.id);
      expect(stored.blocks.map((block) => block.id), contains(inserted.id));
      expect(inserted.type, BlockType.image);
      expect(inserted.content['source'], 'phone-scan');
      final hash = (inserted.content['blob'] as String).substring(7);
      expect(repository.getBlob(notebook.id, hash), const [10, 20, 30]);
    } finally {
      await app.settleBackgroundWork();
      app.dispose();
      AppState.syncLogEnabled = true;
      try {
        temporary.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
