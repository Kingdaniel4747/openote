library;

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../study/study_stats.dart'
    show dayKey, parseDayKey, daysBetween, ExamPlan, examPlan;

abstract interface class StudyDocument {
  String? get notebookId;
  List<TreeNode> get nodes;
  String? get activeSectionId;
}

/// Personal exam dates used by the planner. Flashcard scheduling was removed.
class StudyState extends ChangeNotifier {
  StudyState(this._document,
      {required Object? Function(String) readSetting,
      required void Function(String, Object?) writeSetting})
      : _read = readSetting,
        _write = writeSetting;

  final StudyDocument _document;
  final Object? Function(String) _read;
  final void Function(String, Object?) _write;
  final Map<String, String> _dates = {};
  final Map<String, String> _times = {};
  int studyRevision = 0;

  void noteContentChanged() {}

  void remapCardStates(String blockId, Map<int, int> moved) {}

  void load() {
    _load('examDates', _dates);
    _load('examTimes', _times);
    _times.removeWhere((key, _) => !_dates.containsKey(key));
  }

  void _load(String name, Map<String, String> into) {
    final raw = _read(name);
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is String) into[key] = value;
      });
    }
  }

  String _key(String sectionId) => '${_document.notebookId}:$sectionId';

  DateTime? examDate(String? sectionId) =>
      sectionId == null || _document.notebookId == null
          ? null
          : parseDayKey(_dates[_key(sectionId)] ?? '');

  int? examMinuteOfDay(String? sectionId) {
    if (sectionId == null || _document.notebookId == null) return null;
    final match =
        RegExp(r'^(\d{2}):(\d{2})$').firstMatch(_times[_key(sectionId)] ?? '');
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  DateTime? examAt(String? sectionId) {
    final date = examDate(sectionId);
    final minutes = examMinuteOfDay(sectionId);
    return date == null
        ? null
        : minutes == null
            ? date
            : DateTime(
                date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
  }

  void setExamDate(String sectionId, DateTime? date) {
    if (_document.notebookId == null) return;
    final key = _key(sectionId);
    if (date == null) {
      final changed = _dates.remove(key) != null || _times.remove(key) != null;
      if (!changed) return;
    } else {
      final value = dayKey(date);
      if (_dates[key] == value) return;
      _dates[key] = value;
    }
    _write('examDates', _dates);
    _write('examTimes', _times);
    studyRevision++;
    notifyListeners();
  }

  void setExamTime(String sectionId, int? minuteOfDay) {
    final key = _key(sectionId);
    if (_document.notebookId == null || !_dates.containsKey(key)) return;
    if (minuteOfDay == null) {
      if (_times.remove(key) == null) return;
    } else {
      final minutes = minuteOfDay.clamp(0, 1439);
      final value =
          '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
      if (_times[key] == value) return;
      _times[key] = value;
    }
    _write('examTimes', _times);
    studyRevision++;
    notifyListeners();
  }

  ({TreeNode section, ExamPlan plan})? nextExam([DateTime? now]) {
    final today = now ?? DateTime.now();
    TreeNode? closest;
    DateTime? date;
    for (final node in _document.nodes) {
      if (node.kind != NodeKind.section) continue;
      final candidate = examDate(node.id);
      if (candidate == null || daysBetween(today, candidate) < 0) continue;
      if (date == null || candidate.isBefore(date)) {
        closest = node;
        date = candidate;
      }
    }
    if (closest == null || date == null) return null;
    return (
      section: closest,
      plan: examPlan(exam: date, today: today, unseen: 0, total: 0)!
    );
  }
}
