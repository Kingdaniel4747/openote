import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote_scanner/main.dart';
import 'package:openote_scanner/update_service.dart';

void main() {
  test('accepts a complete Openote pairing code', () {
    final pairing = PairingData.tryParse(
      'openote-scan://pair?host=192.168.1.5&port=27198&'
      'token=abcdefghijklmnopqrstuvwxyz123456&notebook=book&'
      'page=page-1&title=Physics',
    );

    expect(pairing, isNotNull);
    expect(pairing!.pageTitle, 'Physics');
    expect(pairing.uploadUri.toString(), 'http://192.168.1.5:27198/v1/scan');
    expect(
      pairing.completeUri.toString(),
      'http://192.168.1.5:27198/v1/complete',
    );
  });

  test('rejects ordinary and incomplete QR codes', () {
    expect(PairingData.tryParse('https://example.com'), isNull);
    expect(PairingData.tryParse('openote-scan://pair?host=10.0.0.2'), isNull);
  });

  test('finds only a newer scanner APK in a GitHub release', () {
    final release = jsonEncode({
      'tag_name': 'v0.8.30',
      'assets': [
        {
          'name': 'openote-0.8.30-windows-x64-setup.exe',
          'browser_download_url':
              'https://github.com/Kingdaniel4747/openote/releases/download/v0.8.30/openote.exe',
        },
        {
          'name': 'openote-scanner-0.8.30.apk',
          'browser_download_url':
              'https://github.com/Kingdaniel4747/openote/releases/download/v0.8.30/openote-scanner-0.8.30.apk',
        },
      ],
    });

    final update = scannerUpdateFromRelease(release, '0.8.29');
    expect(update?.version, '0.8.30');
    expect(update?.filename, 'openote-scanner-0.8.30.apk');
    expect(scannerUpdateFromRelease(release, '0.8.30'), isNull);
    expect(compareVersions('0.10.0', '0.9.99'), greaterThan(0));
  });
}
