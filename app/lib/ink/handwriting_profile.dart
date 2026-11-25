import 'dart:math' as math;
import 'dart:ui';

import '../model/models.dart';

/// Beta: recorded pen paths, with a shared writing box and baseline.
/// No font outlines or raster images enter the notebook.
class HandwritingProfile {
  HandwritingProfile([Map<String, List<List<Stroke>>>? samples])
      : samples = samples ?? {};

  static const characters =
      'abcdefghijklmnopqrstuvwxyzäöüßABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ0123456789.,:;!?-()\'"/+=%';
  static const boxWidth = 220.0;
  static const boxHeight = 160.0;
  static const baseline = 112.0;
  static const letterHeight = 64.0;
  final Map<String, List<List<Stroke>>> samples;

  List<String> get pendingCharacters => [
        for (final rune in characters.runes)
          if (samples[String.fromCharCode(rune)]?.isNotEmpty != true)
            String.fromCharCode(rune),
      ];

  int get learnedCharacters =>
      characters.runes.length - pendingCharacters.length;
  bool get isComplete => pendingCharacters.isEmpty;

  factory HandwritingProfile.fromJson(dynamic raw) {
    final result = HandwritingProfile();
    if (raw is! Map || raw['v'] != 1 || raw['samples'] is! Map) return result;
    for (final entry in (raw['samples'] as Map).entries) {
      if (entry.key is! String || entry.value is! List) continue;
      for (final variant in entry.value as List) {
        try {
          if (variant is! List) continue;
          result.addSample(entry.key as String, [
            for (final stroke in variant)
              Stroke.fromJson((stroke as Map).cast<String, dynamic>()),
          ]);
        } catch (_) {
          // One damaged sample must not discard the remaining profile.
        }
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'samples': {
          for (final entry in samples.entries)
            entry.key: [
              for (final variant in entry.value)
                [for (final stroke in variant) stroke.toJson()],
            ],
        },
      };

  void addSample(String character, List<Stroke> strokes) {
    saveVariant(character, strokes);
  }

  /// Replacing one chosen variant must not silently evict another variant.
  bool saveVariant(String character, List<Stroke> strokes, {int? index}) {
    if (character.runes.length != 1 ||
        character.trim().isEmpty ||
        strokes.isEmpty ||
        strokes.any((s) =>
            s.x.isEmpty ||
            s.x.length != s.y.length ||
            s.x.any((v) => !v.isFinite || v < 0 || v > boxWidth) ||
            s.y.any((v) => !v.isFinite || v < 0 || v > boxHeight))) {
      return false;
    }
    final variants = samples[character] ?? [];
    if (index != null && (index < 0 || index >= variants.length) ||
        index == null && variants.length >= 5) {
      return false;
    }
    final copy = [
      for (final stroke in strokes) Stroke.fromJson(stroke.toJson()),
    ];
    if (index == null) {
      variants.add(copy);
    } else {
      variants[index] = copy;
    }
    samples[character] = variants;
    return true;
  }

  void removeVariant(String character, int index) {
    final variants = samples[character];
    if (variants == null || index < 0 || index >= variants.length) return;
    variants.removeAt(index);
    if (variants.isEmpty) samples.remove(character);
  }

  Set<String> missing(String text) => {
        for (final rune in text.runes)
          if (String.fromCharCode(rune).trim().isNotEmpty &&
              !samples.containsKey(String.fromCharCode(rune)))
            String.fromCharCode(rune),
      };

  /// Coordinates stay page-absolute, as for strokes recorded on the canvas.
  List<Stroke> generate(
    String text, {
    Offset origin = Offset.zero,
    double height = 28,
    double width = 600,
    double wordSpacing = 1,
    double lineSpacing = 1.5,
    double size = 2.5,
    String color = 'auto',
  }) {
    if (!isComplete || missing(text).isNotEmpty) {
      throw StateError(
          'Complete handwriting setup and record missing characters first.');
    }
    if (!height.isFinite ||
        height <= 0 ||
        !width.isFinite ||
        width <= 0 ||
        !wordSpacing.isFinite ||
        wordSpacing <= 0 ||
        !lineSpacing.isFinite ||
        lineSpacing < 1 ||
        !size.isFinite ||
        size <= 0) {
      throw ArgumentError('Invalid handwriting layout.');
    }
    final scale = height / letterHeight;
    final uses = <String, int>{};
    final result = <Stroke>[];
    var x = 0.0, y = 0.0;
    final lineHeight = boxHeight * scale * lineSpacing;
    void newline() {
      x = 0;
      y += lineHeight;
    }

    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final token in RegExp(r'\n|[^\S\n]+|[^\s]+').allMatches(normalized)) {
      final word = token.group(0)!;
      if (word == '\n') {
        newline();
        continue;
      }
      if (word.trim().isEmpty) {
        x += word.runes.fold<double>(
            0, (sum, r) => sum + height * .45 * wordSpacing * (r == 9 ? 4 : 1));
        continue;
      }
      final glyphs = <(List<Stroke>, double, double)>[];
      for (final rune in word.runes) {
        final character = String.fromCharCode(rune);
        final variants = samples[character]!;
        final index = uses.update(character, (v) => v + 1, ifAbsent: () => 0);
        final strokes = variants[index % variants.length];
        final left = strokes.map((s) => s.bounds().minX).reduce(math.min);
        final right = strokes.map((s) => s.bounds().maxX).reduce(math.max);
        glyphs.add((
          strokes,
          left,
          math.max(height * .15, (right - left) * scale) + height * .12
        ));
      }
      final wordWidth = glyphs.fold<double>(0, (sum, g) => sum + g.$3);
      if (x > 0 && x + wordWidth > width) newline();
      for (final (strokes, left, advance) in glyphs) {
        if (x > 0 && x + advance > width) newline();
        for (final source in strokes) {
          result.add(Stroke(
            tool: 'pen',
            colorHex: color,
            size: size,
            strokeStart: 0,
            x: [for (final v in source.x) origin.dx + x + (v - left) * scale],
            y: [for (final v in source.y) origin.dy + y + v * scale],
            p: List.of(source.p),
            tx: List.of(source.tx),
            ty: List.of(source.ty),
            t: List.of(source.t),
          ));
        }
        x += advance;
      }
    }
    return result;
  }
}
