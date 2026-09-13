import 'package:flutter/material.dart';

import '../core/platform_open.dart';

OverlayEntry? _activeResearchPalette;

/// A small, movable launch pad for looking something up without losing the
/// page one is writing on. Websites deliberately open in the user's browser:
/// that gives YouTube its supported player, sign-in and playback controls,
/// instead of pretending a stripped-down embedded view is a browser.
void showResearchPalette(BuildContext context) {
  if (_activeResearchPalette?.mounted == true) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final query = TextEditingController();
  var position = const Offset(88, 76);
  late OverlayEntry entry;

  Future<void> search(String site) async {
    final words = query.text.trim();
    final encoded = Uri.encodeQueryComponent(words);
    final url = switch (site) {
      'youtube' => 'https://www.youtube.com/results?search_query=$encoded',
      'wikipedia' => 'https://de.wikipedia.org/w/index.php?search=$encoded',
      _ => 'https://www.google.com/search?q=$encoded',
    };
    await PlatformOpen.url(url);
  }

  void close() {
    entry.remove();
    if (identical(_activeResearchPalette, entry)) {
      _activeResearchPalette = null;
    }
    query.dispose();
  }

  entry = OverlayEntry(
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final width = size.width < 400 ? size.width : 400.0;
      final left = position.dx
          .clamp(0.0, (size.width - width).clamp(0.0, size.width))
          .toDouble();
      final top = position.dy
          .clamp(0.0, (size.height - 190).clamp(0.0, size.height))
          .toDouble();
      return Positioned(
        left: left,
        top: top,
        width: width,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 18)
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  position += details.delta;
                  entry.markNeedsBuild();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 6),
                  child: Row(children: [
                    const Icon(Icons.drag_indicator, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Recherche',
                            style: TextStyle(fontWeight: FontWeight.w600))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Schließen',
                      visualDensity: VisualDensity.compact,
                      onPressed: close,
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextField(
                  controller: query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search('google'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Thema suchen …',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      tooltip: 'Mit Google suchen',
                      onPressed: () => search('google'),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                    icon: const Icon(Icons.ondemand_video_outlined, size: 18),
                    label: const Text('YouTube'),
                    onPressed: () => search('youtube'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(
                      child: OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Wikipedia'),
                    onPressed: () => search('wikipedia'),
                  )),
                ]),
              ),
            ]),
          ),
        ),
      );
    },
  );
  _activeResearchPalette = entry;
  overlay.insert(entry);
}
