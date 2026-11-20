import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/models.dart';

/// A PDF slide points at the complete source PDF, not at its preview image.
String? originalSourceKey(Block block) {
  final blob = block.content['pdf'] ?? block.content['blob'];
  if (blob is String && blob.isNotEmpty) {
    return 'blob:${blob.replaceFirst(RegExp(r'^sha256:'), '')}';
  }
  final media = block.content['media'];
  if (media is String && media.isNotEmpty) return 'media:$media';
  final path = block.content['path'];
  if (path is String && path.isNotEmpty) {
    final absolute = p.normalize(p.absolute(path));
    return 'path:${Platform.isWindows ? absolute.toLowerCase() : absolute}';
  }
  return null;
}

List<Block> uniqueOriginals(Iterable<Block> blocks) {
  final seen = <String>{};
  return [
    for (final block in blocks)
      if (originalSourceKey(block) case final String key)
        if (seen.add(key)) block
  ];
}

/// Number across file types and reserve atomically so a concurrent save never
/// replaces an earlier download.
Future<File> reserveOriginalDownload(String directory, String extension) async {
  var number = 1;
  await for (final entry in Directory(directory).list()) {
    final match = RegExp(r'^OpenNote (\d+)\.', caseSensitive: false)
        .firstMatch(p.basename(entry.path));
    if (match != null) {
      final next = int.parse(match.group(1)!) + 1;
      if (next > number) number = next;
    }
  }
  while (true) {
    final file = File(p.join(directory, 'OpenNote $number.$extension'));
    try {
      return await file.create(exclusive: true);
    } on PathExistsException {
      number++;
    }
  }
}
