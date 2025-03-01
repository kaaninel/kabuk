import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kabuk/services/auto_save_service.dart';

void main() {
  group('AutoSaveService', () {
    late AutoSaveService autoSaveService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      autoSaveService = AutoSaveService(prefs);
    });

    test('saves and loads draft content', () async {
      final content = {
        'content': 'Test content',
        'type': 'text',
        'metadata': {'title': 'Test'}
      };

      await autoSaveService.saveDraft('test-id', content);
      final loadedContent = autoSaveService.loadDraft('test-id');

      expect(loadedContent, isNotNull);
      expect(loadedContent?['content'], 'Test content');
      expect(loadedContent?['type'], 'text');
      expect(loadedContent?['metadata']?['title'], 'Test');
    });

    test('clears draft content', () async {
      final content = {'content': 'Test'};
      await autoSaveService.saveDraft('test-id', content);
      await autoSaveService.clearDraft('test-id');

      final loadedContent = autoSaveService.loadDraft('test-id');
      expect(loadedContent, isNull);
    });

    test('updates last save time', () async {
      expect(autoSaveService.getLastSaveTime(), isNull);

      await autoSaveService.saveDraft('test-id', {'content': 'Test'});
      
      expect(autoSaveService.getLastSaveTime(), isNotNull);
      expect(
        autoSaveService.getLastSaveTime()!.isBefore(DateTime.now()), 
        isTrue
      );
    });

    test('starts and stops auto-save timer', () async {
      int saveCount = 0;
      final getContent = () {
        saveCount++;
        return {'content': 'Test $saveCount'};
      };

      autoSaveService.startAutoSave('test-id', getContent);
      await Future.delayed(const Duration(milliseconds: 100));
      autoSaveService.stopAutoSave();

      expect(saveCount, equals(1));
    });
  });
}