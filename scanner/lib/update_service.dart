import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const scannerRepository = 'Kingdaniel4747/openote';
const _latestReleaseUrl =
    'https://api.github.com/repos/$scannerRepository/releases/latest';

class ScannerUpdate {
  const ScannerUpdate({
    required this.version,
    required this.downloadUrl,
    required this.filename,
  });

  final String version;
  final String downloadUrl;
  final String filename;
}

Future<ScannerUpdate?> checkForScannerUpdate() async {
  try {
    final installed = (await PackageInfo.fromPlatform()).version;
    final response = await http
        .get(
          Uri.parse(_latestReleaseUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Openote-Scanner',
          },
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;
    return scannerUpdateFromRelease(response.body, installed);
  } catch (_) {
    // Scanning must remain available offline and when GitHub is unreachable.
    return null;
  }
}

ScannerUpdate? scannerUpdateFromRelease(String body, String installed) {
  try {
    final release = jsonDecode(body) as Map<String, dynamic>;
    final version = (release['tag_name'] as String? ?? '').trim().replaceFirst(
      RegExp(r'^[vV]'),
      '',
    );
    if (version.isEmpty || compareVersions(version, installed) <= 0) {
      return null;
    }
    final assets = release['assets'] as List<dynamic>? ?? const [];
    for (final value in assets) {
      if (value is! Map<String, dynamic>) {
        continue;
      }
      final name = value['name'] as String? ?? '';
      final url = value['browser_download_url'] as String? ?? '';
      final download = Uri.tryParse(url);
      if (name.startsWith('openote-scanner-') &&
          name.endsWith('.apk') &&
          download?.scheme == 'https' &&
          download?.host == 'github.com') {
        return ScannerUpdate(
          version: version,
          downloadUrl: url,
          filename: name,
        );
      }
    }
  } catch (_) {}
  return null;
}

int compareVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

List<int> _versionParts(String value) => value
    .split(RegExp(r'[^0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => int.tryParse(part) ?? 0)
    .toList(growable: false);
