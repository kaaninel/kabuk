/// Agent memory persistence mixin.
///
/// Provides helper methods for agents to persist and retrieve
/// inter-session memory from the knowledge store using the
/// `kabuk:agentMemory` predicate.
///
/// Memory entries are stored as RDF triples with:
/// - Subject: `kabuk:AgentMemory/{agentName}/{key}`
/// - Predicates: `kabuk:agentMemory` (the value), `schema:name` (the key),
///   `schema:dateModified` (last update timestamp)
///
/// Usage:
/// ```dart
/// class MyAgent extends BaseAgent with AgentMemoryMixin {
///   Future<void> example(AgentContext ctx) async {
///     await saveMemory(ctx, 'user_preference', 'dark theme');
///     final pref = await loadMemory(ctx, 'user_preference');
///   }
/// }
/// ```
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/config/namespaces.dart';

/// Mixin that adds persistent memory to agents.
///
/// Agents are stateless between invocations — this mixin stores
/// key-value memory in the knowledge store so agents can recall
/// context across sessions.
///
/// Use [buildSystemPromptWithMemory] in the agent's `process()`
/// method instead of `buildSystemPrompt()` to automatically inject
/// remembered context into the LLM system prompt.
mixin AgentMemoryMixin on BaseAgent {
  /// Maximum number of memory entries per agent.
  ///
  /// When this limit is exceeded during [saveMemory], the oldest entries
  /// (by `schema:dateModified`) are pruned to stay within budget.
  static const int maxMemories = 50;

  /// Generates the subject URI for a memory entry.
  String _memoryUri(String key) => 'kabuk:AgentMemory/$name/$key';

  /// Saves a memory entry to the knowledge store.
  ///
  /// If a value already exists for [key], it is replaced.
  /// The [value] is stored as a string literal.
  ///
  /// If the total number of memories exceeds [maxMemories], the oldest
  /// entries are pruned automatically.
  Future<void> saveMemory(
    AgentContext context,
    String key,
    String value,
  ) async {
    final uri = _memoryUri(key);
    await context.knowledge.mutate((ctx) async {
      await ctx.set(uri, NS.rdfType, 'kabuk:AgentMemory');
      await ctx.set(uri, NS.schemaName, key);
      await ctx.set(uri, NS.kabukAgentMemory, value);
      await ctx.set(
        uri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
    });

    // Prune oldest entries if over budget.
    await _pruneMemories(context);
  }

  /// Prunes oldest memories when the count exceeds [maxMemories].
  ///
  /// Memories are sorted by `schema:dateModified` and the oldest
  /// entries beyond the limit are removed.
  Future<void> _pruneMemories(AgentContext context) async {
    final prefix = 'kabuk:AgentMemory/$name/';
    final allType = await context.knowledge
        .query()
        .where(NS.rdfType, equals: 'kabuk:AgentMemory')
        .execute();

    // Collect subjects belonging to this agent.
    final subjects = allType
        .where((t) => t.subject.startsWith(prefix))
        .map((t) => t.subject)
        .toSet()
        .toList();

    if (subjects.length <= maxMemories) return;

    // Fetch all entities to read their dateModified.
    final entities = await context.knowledge.getEntities(subjects);

    // Build (subject, dateModified) pairs and sort oldest first.
    final dated = <({String subject, DateTime date})>[];
    for (final entry in entities.entries) {
      final dateTuple = entry.value
          .where((t) => t.predicate == NS.schemaDateModified)
          .map((t) => DateTime.tryParse(t.objectValue))
          .firstOrNull;
      dated.add((subject: entry.key, date: dateTuple ?? DateTime(2000)));
    }
    dated.sort((a, b) => a.date.compareTo(b.date));

    // Remove the oldest entries that exceed the limit.
    final toRemove = dated.length - maxMemories;
    if (toRemove <= 0) return;

    await context.knowledge.mutate((ctx) async {
      for (var i = 0; i < toRemove; i++) {
        await ctx.remove(subject: dated[i].subject);
      }
    });
  }

  /// Loads a memory entry from the knowledge store.
  ///
  /// Returns `null` if no value has been stored for [key].
  Future<String?> loadMemory(AgentContext context, String key) async {
    final uri = _memoryUri(key);
    final triples = await context.knowledge.getEntity(uri);
    return triples
        .where((t) => t.predicate == NS.kabukAgentMemory)
        .map((t) => t.objectValue)
        .firstOrNull;
  }

  /// Loads all memory entries for this agent.
  ///
  /// Returns a map of key → value pairs. Useful for building
  /// context summaries when processing a new user message.
  Future<Map<String, String>> loadAllMemories(AgentContext context) async {
    final results = await context.knowledge
        .query()
        .where(NS.rdfType, equals: 'kabuk:AgentMemory')
        .execute();

    // Collect all subject URIs that belong to this agent.
    final prefix = 'kabuk:AgentMemory/$name/';
    final subjects = results
        .where((t) => t.subject.startsWith(prefix))
        .map((t) => t.subject)
        .toSet();

    if (subjects.isEmpty) return {};

    final entities = await context.knowledge.getEntities(subjects.toList());
    final memories = <String, String>{};

    for (final entry in entities.entries) {
      String? key;
      String? value;
      for (final triple in entry.value) {
        if (triple.predicate == NS.schemaName) {
          key = triple.objectValue;
        } else if (triple.predicate == NS.kabukAgentMemory) {
          value = triple.objectValue;
        }
      }
      if (key != null && value != null) {
        memories[key] = value;
      }
    }

    return memories;
  }

  /// Deletes a memory entry.
  ///
  /// Returns silently if the key doesn't exist.
  Future<void> deleteMemory(AgentContext context, String key) async {
    final uri = _memoryUri(key);
    await context.knowledge.mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Builds a memory context string suitable for including in
  /// LLM system prompts.
  ///
  /// Returns an empty string if no memories exist. Otherwise returns
  /// a formatted block listing all key-value pairs.
  Future<String> buildMemoryContext(AgentContext context) async {
    final memories = await loadAllMemories(context);
    if (memories.isEmpty) return '';

    final buffer = StringBuffer('## Agent Memory\n');
    buffer.writeln(
      'The following are things you remember from previous '
      'conversations:\n',
    );
    for (final entry in memories.entries) {
      buffer.writeln('- **${entry.key}**: ${entry.value}');
    }
    return buffer.toString();
  }

  /// Builds the full system prompt with remembered context appended.
  ///
  /// Combines the standard [buildSystemPrompt] output with any
  /// memories stored via [saveMemory]. Use this in [process] instead
  /// of [buildSystemPrompt] to enable cross-session memory recall.
  Future<String> buildSystemPromptWithMemory(
    AgentContext context, {
    bool includeIdentity = true,
  }) async {
    final base = buildSystemPrompt(includeIdentity: includeIdentity);
    final memoryBlock = await buildMemoryContext(context);
    if (memoryBlock.isEmpty) return base;
    return '$base\n\n$memoryBlock';
  }
}
