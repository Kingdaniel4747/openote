library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef ScanReceived = Future<void> Function(
  Uint8List bytes,
  String mime,
  String filename,
);
typedef ScanCompleted = FutureOr<void> Function();

/// A short-lived, LAN-only receiver for the Openote Scanner Android app.
///
/// It exists only while the pairing dialog is open. The random bearer token
/// is embedded in the QR code, requests have a strict size/type limit, and no
/// endpoint can read notebook data back from the computer.
class ScannerReceiver {
  ScannerReceiver({required this.onScan, this.onComplete});

  static const int maxScanBytes = 30 * 1024 * 1024;
  static const int preferredPort = 27198;

  final ScanReceived onScan;
  final ScanCompleted? onComplete;
  final String token = _newToken();
  HttpServer? _server;

  int? get port => _server?.port;

  Future<List<String>> start() async {
    await stop();
    HttpServer? server;
    for (var candidate = preferredPort;
        candidate < preferredPort + 10;
        candidate++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, candidate);
        break;
      } on SocketException {
        // Another local service owns this port; the QR code carries whichever
        // neighbour succeeds, so the phone never has to know the default.
      }
    }
    server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return _lanAddresses();
  }

  Uri pairingUri({
    required String host,
    required String notebookId,
    required String pageId,
    required String pageTitle,
  }) {
    final activePort = port;
    if (activePort == null) throw StateError('Scanner receiver is not running');
    return Uri(
      scheme: 'openote-scan',
      host: 'pair',
      queryParameters: {
        'host': host,
        'port': '$activePort',
        'token': token,
        'notebook': notebookId,
        'page': pageId,
        'title': pageTitle,
      },
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method != 'POST' ||
          (path != '/v1/scan' && path != '/v1/complete')) {
        await _reply(request, HttpStatus.notFound, 'Not found');
        return;
      }
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer $token') {
        await _reply(request, HttpStatus.unauthorized, 'Pairing expired');
        return;
      }
      if (path == '/v1/complete') {
        // Finish the HTTP response before the dialog closes and disposes this
        // server, so the phone receives an unambiguous successful completion.
        await _reply(request, HttpStatus.ok, 'Complete');
        await onComplete?.call();
        return;
      }
      final mime = request.headers.contentType?.mimeType.toLowerCase();
      if (mime != 'image/jpeg' && mime != 'image/png') {
        await _reply(
          request,
          HttpStatus.unsupportedMediaType,
          'Only JPEG and PNG scans are accepted',
        );
        return;
      }
      final advertised = request.contentLength;
      if (advertised > maxScanBytes) {
        await _reply(
            request, HttpStatus.requestEntityTooLarge, 'Scan too large');
        return;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in request) {
        builder.add(chunk);
        if (builder.length > maxScanBytes) {
          await _reply(
            request,
            HttpStatus.requestEntityTooLarge,
            'Scan too large',
          );
          return;
        }
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        await _reply(request, HttpStatus.badRequest, 'Empty scan');
        return;
      }
      final rawName = request.headers.value('x-openote-filename') ?? 'scan.jpg';
      final filename = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
      await onScan(bytes, mime!, filename);
      await _reply(request, HttpStatus.created, 'Imported');
    } catch (error) {
      try {
        await _reply(
          request,
          HttpStatus.internalServerError,
          'Openote could not import this scan: $error',
        );
      } catch (_) {}
    }
  }

  Future<void> _reply(HttpRequest request, int status, String message) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'message': message}));
    await request.response.close();
  }

  static Future<List<String>> _lanAddresses() async {
    final addresses = <String>{};
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    )) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address != '0.0.0.0') {
          addresses.add(address.address);
        }
      }
    }
    final sorted = addresses.toList()
      ..sort((a, b) => _addressScore(a).compareTo(_addressScore(b)));
    return sorted;
  }

  static int _addressScore(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    final parts = address.split('.');
    if (parts.length == 4 && parts.first == '172') {
      final second = int.tryParse(parts[1]);
      if (second != null && second >= 16 && second <= 31) return 2;
    }
    return 3;
  }

  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
