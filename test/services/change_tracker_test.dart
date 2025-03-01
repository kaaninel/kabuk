import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/services/change_tracker.dart';

void main() {
  group('ChangeTracker', () {
    late ChangeTracker tracker;

    setUp(() {
      tracker = ChangeTracker();
    });

    test('initially has no changes', () {
      expect(tracker.hasUnsavedChanges(), isFalse);
      expect(tracker.getLastChangeTime(), isNull);
    });

    test('tracks changes by type', () {
      tracker.markChanged(ChangeType.content);
      expect(tracker.hasChangeType(ChangeType.content), isTrue);
      expect(tracker.hasChangeType(ChangeType.metadata), isFalse);
      expect(tracker.hasChangeType(ChangeType.media), isFalse);
    });

    test('clears all changes', () {
      tracker.markChanged(ChangeType.content);
      tracker.markChanged(ChangeType.metadata);
      expect(tracker.hasUnsavedChanges(), isTrue);

      tracker.clearChanges();
      expect(tracker.hasUnsavedChanges(), isFalse);
      expect(tracker.hasChangeType(ChangeType.content), isFalse);
      expect(tracker.hasChangeType(ChangeType.metadata), isFalse);
    });

    test('updates last change time', () {
      expect(tracker.getLastChangeTime(), isNull);
      
      tracker.markChanged(ChangeType.content);
      final firstChangeTime = tracker.getLastChangeTime();
      expect(firstChangeTime, isNotNull);

      // Wait a moment to ensure different timestamp
      Future.delayed(const Duration(milliseconds: 1), () {
        tracker.markChanged(ChangeType.metadata);
        expect(tracker.getLastChangeTime()!.isAfter(firstChangeTime!), isTrue);
      });
    });

    test('notifies listeners of changes', () {
      var notificationCount = 0;
      tracker.addListener(() {
        notificationCount++;
      });

      tracker.markChanged(ChangeType.content);
      expect(notificationCount, 1);

      tracker.clearChanges();
      expect(notificationCount, 2);
    });
  });
}