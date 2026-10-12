/// A planner checklist entry without a date or a scheduled notification.
class UndatedEntry {
  const UndatedEntry({
    required this.id,
    required this.text,
    this.category = 'todo',
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;
  final String category;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'category': category,
        'done': done,
      };

  static UndatedEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || text is! String || text.trim().isEmpty) {
      return null;
    }
    final category = raw['category'];
    return UndatedEntry(
        id: id,
        text: text,
        category: category == 'homework' || category == 'exam'
            ? category as String
            : 'todo',
        done: raw['done'] == true);
  }
}
