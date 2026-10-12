/// A planner checklist entry without a date or a scheduled notification.
class UndatedEntry {
  const UndatedEntry({required this.id, required this.text, this.done = false});

  final String id;
  final String text;
  final bool done;

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done};

  static UndatedEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || text is! String || text.trim().isEmpty) {
      return null;
    }
    return UndatedEntry(id: id, text: text, done: raw['done'] == true);
  }
}
