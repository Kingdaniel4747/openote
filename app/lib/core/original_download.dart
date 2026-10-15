import 'dart:io';

import 'package:path/path.dart' as p;

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
