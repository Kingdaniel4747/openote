import 'package:flutter_test/flutter_test.dart';
import 'package:openote_scanner/main.dart';

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
  });

  test('rejects ordinary and incomplete QR codes', () {
    expect(PairingData.tryParse('https://example.com'), isNull);
    expect(PairingData.tryParse('openote-scan://pair?host=10.0.0.2'), isNull);
  });
}
