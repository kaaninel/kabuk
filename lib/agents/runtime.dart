/// Agent runtime — manages agent lifecycle and execution.
///
/// In the future this will use Dart isolates for sandboxing.
/// Currently runs agents in the main isolate.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/messages.dart';

/// A lightweight summary of an agent for display in the UI.
///
/// Avoids exposing the full [BaseAgent] to the presentation layer.
class AgentSummary {
  /// Creates an [AgentSummary].
  const AgentSummary({
    required this.name,
    required this.description,
    required this.toolCount,
    required this.tools,
    required this.capabilities,
  });

  /// Creates an [AgentSummary] from a [BaseAgent].
  factory AgentSummary.fromAgent(BaseAgent agent) => AgentSummary(
    name: agent.name,
    description: agent.description,
    toolCount: agent.tools.length,
    tools: agent.tools
        .map((t) => AgentToolSummary(name: t.name, description: t.description))
        .toList(),
    capabilities: agent.requiredCapabilities.map((c) => c.name).toList(),
  );

  /// The agent's name.
  final String name;

  /// A human-readable description.
  final String description;

  /// The number of tools this agent provides.
  final int toolCount;

  /// Summaries of each tool.
  final List<AgentToolSummary> tools;

  /// Capability keywords.
  final List<String> capabilities;
}

/// Lightweight summary of a single agent tool.
class AgentToolSummary {
  /// Creates an [AgentToolSummary].
  const AgentToolSummary({required this.name, required this.description});

  /// Tool name.
  final String name;

  /// Tool description.
  final String description;
}

/// Manages agent lifecycle and execution.
///
/// The runtime is responsible for registering agents, looking them up
/// by name, and dispatching messages to the correct agent. Future
/// versions will run each agent in a separate Dart isolate for
/// sandboxing and parallelism.
abstract interface class AgentRuntime {
  /// Register an [agent] so it can be invoked by name.
  void register(BaseAgent agent);

  /// Get an agent by [name], or `null` if not registered.
  BaseAgent? getAgent(String name);

  /// List all registered agents.
  List<BaseAgent> get agents;

  /// Returns UI-safe summaries of all registered agents.
  List<AgentSummary> get registeredAgents;

  /// Invoke an agent by [agentName] with a [message] and [context].
  ///
  /// Throws if no agent with the given name is registered.
  Future<AgentResponse> invoke(
    String agentName,
    AgentMessage message,
    AgentContext context,
  );

  /// Release any resources held by the runtime (e.g. isolates).
  void dispose();
}
