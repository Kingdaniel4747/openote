import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

OverlayEntry? _activeResearchPalette;

/// A movable, resizable browser that stays above the current note.
void showResearchPalette(BuildContext context) {
  if (_activeResearchPalette?.mounted == true) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ResearchPalette(
      onClose: () {
        entry.remove();
        if (identical(_activeResearchPalette, entry)) {
          _activeResearchPalette = null;
        }
      },
    ),
  );
  _activeResearchPalette = entry;
  overlay.insert(entry);
}

class _ResearchPalette extends StatefulWidget {
  const _ResearchPalette({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_ResearchPalette> createState() => _ResearchPaletteState();
}

class _ResearchPaletteState extends State<_ResearchPalette> {
  final _address = TextEditingController(text: 'https://www.youtube.com/');
  final _controller = WebviewController();
  Offset _position = const Offset(88, 76);
  Size _size = const Size(640, 460);
  String? _problem;
  bool _ready = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _openBrowser();
  }

  Future<void> _openBrowser() async {
    if (!Platform.isWindows) {
      setState(() => _problem =
          'The embedded browser is currently available on Windows only.');
      return;
    }
    try {
      if (await WebviewController.getWebViewVersion() == null) {
        setState(() =>
            _problem = 'Microsoft Edge WebView2 is missing on this computer.');
        return;
      }
      await _controller.initialize();
      _initialised = true;
      await _controller.loadUrl(_address.text);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _problem =
            'The embedded browser could not be started on this computer.');
      }
    }
  }

  String _urlFor(String input) {
    final value = input.trim();
    if (value.isEmpty) return 'https://www.youtube.com/';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return uri.toString();
    if (value.contains('.') && !value.contains(' ')) return 'https://$value';
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(value)}';
  }

  Future<void> _go([String? address]) async {
    if (!_ready) return;
    final url = _urlFor(address ?? _address.text);
    _address.text = url;
    await _controller.loadUrl(url);
  }

  @override
  void dispose() {
    _address.dispose();
    if (_initialised) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = _size.width.clamp(360.0, viewport.width).toDouble();
    final height = _size.height.clamp(250.0, viewport.height).toDouble();
    final left = _position.dx
        .clamp(0.0, (viewport.width - width).clamp(0.0, viewport.width))
        .toDouble();
    final top = _position.dy
        .clamp(0.0, (viewport.height - height).clamp(0.0, viewport.height))
        .toDouble();
    final theme = Theme.of(context);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 18)
            ],
          ),
          child: Stack(children: [
            Column(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => setState(() {
                  _position += details.delta;
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 3, 3),
                  child: Row(children: [
                    const Icon(Icons.drag_indicator, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Research',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    tooltip: 'Back',
                    onPressed: _ready ? _controller.goBack : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    tooltip: 'Forward',
                    onPressed: _ready ? _controller.goForward : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _address,
                      textInputAction: TextInputAction.go,
                      onSubmitted: _go,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText:
                            'YouTube, Google, Wikipedia, or a web address',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    tooltip: 'Open',
                    onPressed: _ready ? _go : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Reload',
                    onPressed: _ready ? _controller.reload : null,
                  ),
                ]),
              ),
              Expanded(child: _browser()),
            ]),
            Positioned(
              right: 1,
              bottom: 1,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => setState(() {
                    _size += details.delta;
                  }),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.drag_handle, size: 17),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _browser() {
    if (_problem case final text?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Webview(_controller),
    );
  }
}
