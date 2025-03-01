import 'package:flutter/material.dart';

enum ChangeType {
  content,
  metadata,
  media,
}

class ChangeTracker extends ChangeNotifier {
  final Map<ChangeType, bool> _changes = {
    ChangeType.content: false,
    ChangeType.metadata: false,
    ChangeType.media: false,
  };
  DateTime? _lastChangeTime;

  bool hasUnsavedChanges() {
    return _changes.values.any((changed) => changed);
  }

  void markChanged(ChangeType type) {
    _changes[type] = true;
    _lastChangeTime = DateTime.now();
    notifyListeners();
  }

  void clearChanges() {
    for (var key in _changes.keys) {
      _changes[key] = false;
    }
    notifyListeners();
  }

  DateTime? getLastChangeTime() => _lastChangeTime;

  bool hasChangeType(ChangeType type) => _changes[type] ?? false;
}