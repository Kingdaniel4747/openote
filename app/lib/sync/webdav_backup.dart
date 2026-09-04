import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class WebDavNotebook {
  const WebDavNotebook({
    required this.id,
    required this.title,
    required this.container,
    required this.logDirectory,
  });

  final String id;
  final String title;
  final File container;
  final Directory? logDirectory;
}

class WebDavUploadResult {
  const WebDavUploadResult({required this.files, required this.bytes});
  final int files;
  final int bytes;
}

/// Small dependency-free WebDAV uploader for Nextcloud and ordinary WebDAV
/// servers. It deliberately uploads snapshots and never exposes the live WAL
/// SQLite file to a remote filesystem.
class WebDavBackupClient {
  WebDavBackupClient({
    required this.baseUrl,
    required this.username,
    required this.password,
  }) : _base = _normaliseBase(baseUrl);

  final String baseUrl;
  final String username;
  final String password;
  final Uri _base;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  static Uri _normaliseBase(String value) {
    final uri = Uri.parse(value.trim());
    if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      throw const FormatException(
          'Enter a complete http:// or https:// WebDAV URL.');
    }
    return uri.replace(query: null, fragment: null);
  }

  String get _authorization =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Uri _at(List<String> extra) => _base.replace(pathSegments: [
        ..._base.pathSegments.where((part) => part.isNotEmpty),
        ...extra,
      ]);

  Future<void> testConnection() async {
    final status =
        await _emptyRequest('PROPFIND', _base, headers: const {'Depth': '0'});
    if (status != HttpStatus.ok && status != 207) {
      throw WebDavException('The server rejected the connection', status);
    }
  }

  Future<WebDavUploadResult> uploadAll(
    List<WebDavNotebook> notebooks, {
    void Function(String message)? onProgress,
  }) async {
    await testConnection();
    await _ensureCollection(const ['Openote']);
    var files = 0;
    var bytes = 0;

    for (final notebook in notebooks) {
      onProgress?.call('Uploading ${notebook.title}…');
      final root = ['Openote', notebook.id];
      await _ensureCollection(root);

      final manifest = utf8.encode(jsonEncode({
        'id': notebook.id,
        'title': notebook.title,
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
      }));
      await _putBytes([...root, 'notebook.json'], manifest);
      files++;
      bytes += manifest.length;

      await _putFile([...root, 'notebook.onote'], notebook.container);
      files++;
      bytes += await notebook.container.length();

      final logs = notebook.logDirectory;
      if (logs != null && await logs.exists()) {
        await _ensureCollection([...root, 'notebook.onotebook']);
        final directories = <String>{};
        await for (final entity
            in logs.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final relative = p.relative(entity.path, from: logs.path);
          final parts = p.split(relative);
          if (_skip(parts, entity.path)) continue;
          if (parts.length > 1) {
            final parent = parts.take(parts.length - 1).join('/');
            if (directories.add(parent)) {
              for (var i = 1; i < parts.length; i++) {
                await _ensureCollection([
                  ...root,
                  'notebook.onotebook',
                  ...parts.take(i),
                ]);
              }
            }
          }
          await _putFile([...root, 'notebook.onotebook', ...parts], entity);
          files++;
          bytes += await entity.length();
        }
      }
    }
    return WebDavUploadResult(files: files, bytes: bytes);
  }

  bool _skip(List<String> parts, String path) {
    if (parts.any((part) => part == '.git' || part == '.DS_Store')) return true;
    final lower = path.toLowerCase();
    return lower.endsWith('-wal') ||
        lower.endsWith('-shm') ||
        lower.endsWith('.tmp');
  }

  Future<void> _ensureCollection(List<String> path) async {
    final status = await _emptyRequest('MKCOL', _at(path));
    // 405 means the collection already exists on Nextcloud and most WebDAV
    // servers. 301 is also accepted for servers that canonicalise a slash.
    if (status != HttpStatus.created &&
        status != HttpStatus.methodNotAllowed &&
        status != HttpStatus.movedPermanently) {
      throw WebDavException('Could not create ${path.join('/')}', status);
    }
  }

  Future<void> _putFile(List<String> path, File file) async {
    final request = await _open('PUT', _at(path));
    request.contentLength = await file.length();
    await request.addStream(file.openRead());
    final response = await request.close().timeout(const Duration(minutes: 5));
    final status = response.statusCode;
    await response.drain<void>();
    if (status != HttpStatus.ok &&
        status != HttpStatus.created &&
        status != HttpStatus.noContent) {
      throw WebDavException('Could not upload ${path.last}', status);
    }
  }

  Future<void> _putBytes(List<String> path, List<int> bytes) async {
    final request = await _open('PUT', _at(path));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 60));
    final status = response.statusCode;
    await response.drain<void>();
    if (status != HttpStatus.ok &&
        status != HttpStatus.created &&
        status != HttpStatus.noContent) {
      throw WebDavException('Could not upload ${path.last}', status);
    }
  }

  Future<HttpClientRequest> _open(String method, Uri uri) async {
    final request =
        await _http.openUrl(method, uri).timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    request.headers.set(HttpHeaders.userAgentHeader, 'Openote WebDAV backup');
    return request;
  }

  Future<int> _emptyRequest(String method, Uri uri,
      {Map<String, String> headers = const {}}) async {
    final request = await _open(method, uri);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 60));
    final status = response.statusCode;
    await response.drain<void>();
    return status;
  }

  void close() => _http.close(force: true);
}

class WebDavException implements Exception {
  const WebDavException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => '$message (HTTP $statusCode).';
}
