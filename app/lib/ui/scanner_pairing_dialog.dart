import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/scanner_import.dart';
import '../api/scanner_receiver.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

Future<void> showScannerPairingDialog(
    BuildContext context, AppState app) async {
  final notebookId = app.notebookId;
  final pageId = app.pageId;
  if (notebookId == null || pageId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open a page before starting the scanner.')),
    );
    return;
  }
  final title = app.node(pageId)?.title ?? 'Openote page';
  await showOnoteDialog<void>(
    context: context,
    builder: (_) => _ScannerPairingDialog(
      app: app,
      notebookId: notebookId,
      pageId: pageId,
      pageTitle: title,
    ),
  );
}

class _ScannerPairingDialog extends StatefulWidget {
  const _ScannerPairingDialog({
    required this.app,
    required this.notebookId,
    required this.pageId,
    required this.pageTitle,
  });

  final AppState app;
  final String notebookId;
  final String pageId;
  final String pageTitle;

  @override
  State<_ScannerPairingDialog> createState() => _ScannerPairingDialogState();
}

class _ScannerPairingDialogState extends State<_ScannerPairingDialog> {
  late final ScannerReceiver _receiver;
  List<String> _hosts = const [];
  String? _host;
  String? _error;
  int _received = 0;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _receiver = ScannerReceiver(onScan: (bytes, mime, _) async {
      if (mounted) setState(() => _importing = true);
      try {
        await importPhoneScan(
          widget.app,
          notebookId: widget.notebookId,
          pageId: widget.pageId,
          bytes: bytes,
          mime: mime,
        );
        if (mounted) setState(() => _received++);
      } finally {
        if (mounted) setState(() => _importing = false);
      }
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final hosts = await _receiver.start();
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _host = hosts.firstOrNull;
        if (hosts.isEmpty) {
          _error = 'No local network was found. Connect both devices to the '
              'same Wi-Fi network and try again.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not start scanner: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_receiver.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final pairing = host == null
        ? null
        : _receiver.pairingUri(
            host: host,
            notebookId: widget.notebookId,
            pageId: widget.pageId,
            pageTitle: widget.pageTitle,
          );
    return AlertDialog(
      title: const Text('Scan from phone'),
      content: SizedBox(
        width: 390,
        child: _error != null
            ? Text(_error!)
            : pairing == null
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.pageTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(
                          data: pairing.toString(),
                          size: 220,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Open Openote Scanner on your phone and scan this code. '
                        'Both devices must use the same Wi-Fi network.',
                        textAlign: TextAlign.center,
                      ),
                      if (_hosts.length > 1) ...[
                        const SizedBox(height: 10),
                        DropdownButton<String>(
                          value: host,
                          items: [
                            for (final address in _hosts)
                              DropdownMenuItem(
                                value: address,
                                child: Text(address),
                              ),
                          ],
                          onChanged: (value) => setState(() => _host = value),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_importing)
                        const LinearProgressIndicator()
                      else
                        Text(
                          _received == 0
                              ? 'Waiting for scans…'
                              : '$_received page${_received == 1 ? '' : 's'} imported',
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
