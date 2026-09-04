import 'dart:convert';
import 'dart:io';

class WebDavUploadResult {
  const WebDavUploadResult({required this.files, required this.bytes});
  final int files;
  final int bytes;
}

class WorkspaceBackupResult {
  const WorkspaceBackupResult({required this.notebooks, required this.bytes});
  final int notebooks;
  final int bytes;
}

/// Small WebDAV client for one complete, portable workspace archive.
///
/// One ZIP means a notebook containing hundreds of PDF previews still costs
/// one upload request instead of hundreds of slow WebDAV round trips.
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

  static const remoteFolder = 'Openote';
  static const remoteFile = 'Openote Backup.zip';

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

  bool get _baseIsOpenote =>
      _base.pathSegments
          .where((part) => part.isNotEmpty)
          .lastOrNull
          ?.toLowerCase() ==
      remoteFolder.toLowerCase();

  List<String> get _remoteRoot =>
      _baseIsOpenote ? const [] : const [remoteFolder];

  Future<void> testConnection() async {
    final status =
        await _emptyRequest('PROPFIND', _base, headers: const {'Depth': '0'});
    if (status != HttpStatus.ok && status != 207) {
      throw WebDavException('The server rejected the connection', status);
    }
  }

  Future<int> uploadBackup(File archive,
      {void Function(String message)? onProgress}) async {
    await testConnection();
    if (!_baseIsOpenote) await _ensureCollection(_remoteRoot);
    onProgress?.call('Uploading one complete workspace backup...');
    await _putFile([..._remoteRoot, remoteFile], archive);
    return archive.length();
  }

  Future<int> downloadBackup(File destination,
      {void Function(String message)? onProgress}) async {
    await testConnection();
    onProgress?.call('Downloading the complete workspace backup...');
    final request = await _open('GET', _at([..._remoteRoot, remoteFile]));
    final response = await request.close().timeout(const Duration(minutes: 2));
    if (response.statusCode != HttpStatus.ok) {
      final status = response.statusCode;
      await response.drain<void>();
      throw WebDavException('Could not download $remoteFile', status);
    }
    final sink = destination.openWrite();
    await response.pipe(sink).timeout(const Duration(minutes: 10));
    return destination.length();
  }

  Future<void> _ensureCollection(List<String> path) async {
    final status = await _emptyRequest('MKCOL', _at(path));
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
    final response = await request.close().timeout(const Duration(minutes: 10));
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
