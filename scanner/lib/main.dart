import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

void main() => runApp(const OpenoteScannerApp());

class OpenoteScannerApp extends StatelessWidget {
  const OpenoteScannerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Openote Scanner',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF65558F)),
      useMaterial3: true,
    ),
    home: const ScannerHome(),
  );
}

class PairingData {
  const PairingData({
    required this.host,
    required this.port,
    required this.token,
    required this.notebookId,
    required this.pageId,
    required this.pageTitle,
  });

  final String host;
  final int port;
  final String token;
  final String notebookId;
  final String pageId;
  final String pageTitle;

  Uri get uploadUri =>
      Uri(scheme: 'http', host: host, port: port, path: '/v1/scan');
  Uri get completeUri =>
      Uri(scheme: 'http', host: host, port: port, path: '/v1/complete');

  static PairingData? tryParse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'openote-scan' || uri.host != 'pair') {
      return null;
    }
    final host = uri.queryParameters['host']?.trim() ?? '';
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final token = uri.queryParameters['token'] ?? '';
    final notebook = uri.queryParameters['notebook'] ?? '';
    final page = uri.queryParameters['page'] ?? '';
    if (host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        token.length < 32 ||
        notebook.isEmpty ||
        page.isEmpty) {
      return null;
    }
    return PairingData(
      host: host,
      port: port,
      token: token,
      notebookId: notebook,
      pageId: page,
      pageTitle: uri.queryParameters['title'] ?? 'Openote page',
    );
  }
}

class ScannerHome extends StatefulWidget {
  const ScannerHome({super.key});

  @override
  State<ScannerHome> createState() => _ScannerHomeState();
}

class _ScannerHomeState extends State<ScannerHome> {
  PairingData? _pairing;
  bool _busy = false;
  int _sent = 0;
  int _total = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Opening the companion app means scanning. Avoid a redundant landing
    // page and put the camera on screen immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pair());
  }

  Future<void> _pair() async {
    final pairing = await Navigator.push<PairingData>(
      context,
      MaterialPageRoute(builder: (_) => const PairQrPage()),
    );
    if (!mounted || pairing == null) return;
    setState(() {
      _pairing = pairing;
      _message = null;
      _sent = 0;
      _total = 0;
    });
    await _scan();
  }

  Future<void> _scan() async {
    final pairing = _pairing;
    if (pairing == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _sent = 0;
      _total = 0;
    });
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        pageLimit: 20,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final paths = result.images ?? const [];
      if (paths.isEmpty) {
        if (mounted) setState(() => _message = 'No pages were scanned.');
        return;
      }
      if (mounted) setState(() => _total = paths.length);
      for (var index = 0; index < paths.length; index++) {
        final source = paths[index];
        final parsed = Uri.tryParse(source);
        final file = parsed != null && parsed.scheme == 'file'
            ? File.fromUri(parsed)
            : File(source);
        final bytes = await file.readAsBytes();
        final response = await http
            .post(
              pairing.uploadUri,
              headers: {
                HttpHeaders.authorizationHeader: 'Bearer ${pairing.token}',
                HttpHeaders.contentTypeHeader: 'image/jpeg',
                'x-openote-filename': 'scan-${index + 1}.jpg',
              },
              body: bytes,
            )
            .timeout(const Duration(seconds: 90));
        if (response.statusCode != HttpStatus.created) {
          throw HttpException(
            'Openote answered ${response.statusCode}: ${response.body}',
          );
        }
        if (mounted) setState(() => _sent = index + 1);
      }
      final completion = await http
          .post(
            pairing.completeUri,
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer ${pairing.token}',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (completion.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Openote could not finish the import (${completion.statusCode}).',
        );
      }
      if (mounted) {
        setState(
          () => _message =
              '${paths.length} page${paths.length == 1 ? '' : 's'} imported.',
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _message =
              'The computer did not answer. Keep the pairing window open and '
              'check that both devices use the same Wi-Fi.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Import failed: $error');
    } finally {
      await scanner.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    return Scaffold(
      appBar: AppBar(title: const Text('Openote Scanner')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    pairing == null
                        ? Icons.qr_code_scanner
                        : Icons.document_scanner_outlined,
                    size: 88,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    pairing == null
                        ? 'Connect to an Openote page'
                        : pairing.pageTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    pairing == null
                        ? 'In Openote on your computer, open the target page '
                              'and choose Scan from phone.'
                        : 'Scanned sheets are inserted below the existing '
                              'content on this page.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (pairing == null)
                    FilledButton.icon(
                      onPressed: _pair,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan pairing code'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(_busy ? 'Sending…' : 'Scan document'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _pairing = null;
                              _message = null;
                            }),
                      child: const Text('Disconnect'),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: _total == 0 ? null : _sent / _total,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _total == 0
                          ? 'Preparing scans…'
                          : 'Sending $_sent of $_total…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 20),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PairQrPage extends StatefulWidget {
  const PairQrPage({super.key});

  @override
  State<PairQrPage> createState() => _PairQrPageState();
}

class _PairQrPageState extends State<PairQrPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  String? _error;

  Future<void> _detected(BarcodeCapture capture) async {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    final pairing = value == null ? null : PairingData.tryParse(value);
    if (pairing == null) {
      setState(() => _error = 'This is not an Openote scanner code.');
      return;
    }
    _handled = true;
    await _controller.stop();
    if (mounted) Navigator.pop(context, pairing);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan pairing code')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _detected),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        if (_error != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    ),
  );
}
