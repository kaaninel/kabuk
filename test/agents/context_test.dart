import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAgentContextBundle bundle;
  late AgentContext context;

  setUp(() {
    bundle = createMockAgentContext();
    context = bundle.context;
  });

  // ---------------------------------------------------------------------------
  // Service accessibility
  // ---------------------------------------------------------------------------

  group('AgentContext service fields', () {
    test('all service fields are accessible', () {
      expect(context.knowledge, same(bundle.knowledge));
      expect(context.vault, same(bundle.vault));
      expect(context.mesh, same(bundle.mesh));
      expect(context.media, same(bundle.media));
      expect(context.auth, same(bundle.auth));
      expect(context.notification, same(bundle.notification));
      expect(context.llm, same(bundle.llm));
      expect(context.runtime, same(bundle.runtime));
    });

    test('presentation field is present and accessible', () {
      expect(context.presentation, same(bundle.presentation));
    });
  });

  // ---------------------------------------------------------------------------
  // copyWithCallbacks
  // ---------------------------------------------------------------------------

  group('copyWithCallbacks', () {
    test('preserves all services', () {
      final copy = context.copyWithCallbacks();

      expect(copy.knowledge, same(context.knowledge));
      expect(copy.vault, same(context.vault));
      expect(copy.mesh, same(context.mesh));
      expect(copy.media, same(context.media));
      expect(copy.auth, same(context.auth));
      expect(copy.notification, same(context.notification));
      expect(copy.presentation, same(context.presentation));
      expect(copy.llm, same(context.llm));
      expect(copy.runtime, same(context.runtime));
    });

    test('sets new callbacks', () {
      void onCall(String name, Map<String, dynamic> args) {}
      void onResult(String name, ToolResult result) {}

      final copy = context.copyWithCallbacks(
        onToolCall: onCall,
        onToolResult: onResult,
      );

      expect(copy.onToolCall, same(onCall));
      expect(copy.onToolResult, same(onResult));
    });

    test('keeps existing callbacks when nulls passed', () {
      void onCall(String name, Map<String, dynamic> args) {}
      void onResult(String name, ToolResult result) {}

      final withCallbacks = AgentContext(
        knowledge: bundle.knowledge,
        vault: bundle.vault,
        mesh: bundle.mesh,
        media: bundle.media,
        auth: bundle.auth,
        notification: bundle.notification,
        presentation: bundle.presentation,
        llm: bundle.llm,
        runtime: bundle.runtime,
        onToolCall: onCall,
        onToolResult: onResult,
      );

      // Pass null explicitly — should keep existing callbacks.
      final copy = withCallbacks.copyWithCallbacks();

      expect(copy.onToolCall, same(onCall));
      expect(copy.onToolResult, same(onResult));
    });
  });
}
