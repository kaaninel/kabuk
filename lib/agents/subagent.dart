/// Subagent delegation — lets the on-device agent ask a remote model.
///
/// The on-device model (MiniCPM5 1B) is the primary agent. For tasks that
/// exceed its ability — complex reasoning, long-form writing, deep research —
/// it can delegate to a remote "subagent" through the OpenAI-compatible
/// endpoint configured as the advanced tier. The subagent's answer is fed
/// back into the agent's tool loop so the local model can synthesize and
/// act on it.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/tiered_llm.dart';

/// The subagent delegation tool exposed to agents.
///
/// Agents append this to their `tools` list to gain the ability to delegate
/// a task to the remote advanced-tier model. The result is returned as text
/// so the agent's tool-call loop can continue with the answer in context.
final AgentTool kDelegateToSubagentTool = AgentTool(
  name: 'delegate_to_subagent',
  description:
      'Delegate a task to a remote subagent model (the advanced-tier '
      'OpenAI-compatible endpoint). Use for complex reasoning, long-form '
      'writing, or tasks the on-device model handles poorly. '
      'Returns the remote model\'s answer.',
  parameters: {
    'type': 'object',
    'properties': {
      'task': {
        'type': 'string',
        'description': 'The task or question for the subagent to solve.',
      },
      'system': {
        'type': 'string',
        'description':
            'Optional system instructions framing the subagent\'s role.',
      },
      'temperature': {
        'type': 'number',
        'description': 'Sampling temperature (default 0.5).',
      },
    },
    'required': ['task'],
  },
  execute: _delegateToSubagent,
);

Future<ToolResult> _delegateToSubagent(
  Map<String, dynamic> args,
  AgentContext context,
) async {
  final task = (args['task'] as String?)?.trim() ?? '';
  if (task.isEmpty) {
    return const ToolResult.error('A task is required.');
  }

  // The advanced tier is the remote OpenAI-compatible endpoint. If no
  // remote model is configured, this falls back to the on-device model.
  final llm = context.llmForTier(LlmTier.advanced);

  final system = (args['system'] as String?)?.trim();
  final temperature = (args['temperature'] as num?)?.toDouble();

  final messages = <LlmMessage>[
    if (system != null && system.isNotEmpty) LlmMessage.system(system),
    LlmMessage.user(task),
  ];

  final response = await llm.complete(
    LlmRequest(
      messages: messages,
      temperature: temperature ?? 0.5,
      maxTokens: 2048,
    ),
  );

  return switch (response) {
    TextLlmResponse(:final content) => ToolResult.text(content.trim()),
    ToolCallsLlmResponse(:final content) => ToolResult.text(
        'Subagent requested tools: ${(content ?? '').trim()}',
      ),
    ErrorLlmResponse(:final message) => ToolResult.error(
        'Subagent failed: $message',
      ),
  };
}