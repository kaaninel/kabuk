import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AutoSaveService {
  static const _saveInterval = Duration(seconds: 30);
  static const _draftKeyPrefix = 'draft_';
  
  final SharedPreferences _prefs;
  Timer? _autoSaveTimer;
  DateTime? _lastSaveTime;
  final Map<String, DateTime> _lastModifiedTimes = {};
  
  AutoSaveService(this._prefs);

  static Future<AutoSaveService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return AutoSaveService(prefs);
  }

  void startAutoSave(String id, Function() getContent) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(_saveInterval, (_) {
      saveDraft(id, getContent());
    });
  }

  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  Future<void> saveDraft(String id, Map<String, dynamic> content) async {
    final key = _draftKeyPrefix + id;
    await _prefs.setString(key, jsonEncode(content));
    _lastSaveTime = DateTime.now();
    _lastModifiedTimes[id] = _lastSaveTime!;
  }

  Map<String, dynamic>? loadDraft(String id) {
    final key = _draftKeyPrefix + id;
    final draftStr = _prefs.getString(key);
    if (draftStr == null) return null;
    
    try {
      return jsonDecode(draftStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> getAllDrafts() async {
    final keys = _prefs.getKeys();
    return keys
        .where((key) => key.startsWith(_draftKeyPrefix))
        .map((key) => key.substring(_draftKeyPrefix.length))
        .toList();
  }

  Future<void> clearDraft(String id) async {
    final key = _draftKeyPrefix + id;
    await _prefs.remove(key);
    _lastModifiedTimes.remove(id);
  }

  DateTime? getLastSaveTime() => _lastSaveTime;
  
  DateTime? getLastModifiedTime(String id) => _lastModifiedTimes[id];
}