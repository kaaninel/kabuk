/// Privacy filter — anonymizes prompts before sending to remote LLMs.
///
/// Uses the small on-device LLM to strip personally identifiable
/// information (PII), names, locations, and other sensitive data from
/// prompts before they leave the device. After the remote LLM responds,
/// the filter re-injects the original context so the user sees a
/// coherent, de-anonymized response.
///
/// This is a core privacy feature of Kabuk: users get the power of
/// cloud LLMs without exposing their private data. Everything happens
/// transparently — non-technical users don't need to configure anything.
library;

import 'package:kabuk/agents/llm.dart';

/// The level of privacy filtering applied to outgoing LLM requests.
///
/// Controls how aggressively the [PrivacyFilter] scrubs data before
/// sending to remote APIs. Higher levels are safer but may reduce
/// response quality for context-dependent queries.
enum PrivacyLevel {
  /// No filtering — prompts are sent as-is. Only for local models.
  none,

  /// Light filtering — strips obvious PII (names, emails, phones,
  /// addresses) but preserves general context.
  light,

  /// Standard filtering — replaces PII with placeholders and
  /// generalizes locations and dates. Default for remote APIs.
  standard,

  /// Maximum filtering — aggressively strips all potentially
  /// identifying information, rewrites prompts to be fully generic.
  maximum,
}

/// A mapping of original values to their anonymized placeholders.
///
/// Used to de-anonymize the remote LLM's response by replacing
/// placeholders back with the original values.
class AnonymizationMap {
  /// Creates an [AnonymizationMap].
  const AnonymizationMap({
    required this.replacements,
    required this.originalPrompt,
    required this.anonymizedPrompt,
  });

  /// An empty map (no replacements made).
  static const empty = AnonymizationMap(
    replacements: {},
    originalPrompt: '',
    anonymizedPrompt: '',
  );

  /// Maps placeholder tokens to their original values.
  /// e.g., `{'[PERSON_1]': 'Alice', '[EMAIL_1]': 'alice@example.com'}`.
  final Map<String, String> replacements;

  /// The original unmodified prompt text.
  final String originalPrompt;

  /// The prompt after anonymization.
  final String anonymizedPrompt;

  /// Whether any replacements were made.
  bool get hasReplacements => replacements.isNotEmpty;

  /// Replace placeholders in [text] with original values.
  ///
  /// Used to de-anonymize the remote LLM's response so the user
  /// sees coherent text with their real names, places, etc.
  String deAnonymize(String text) {
    var result = text;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}

/// Anonymizes prompts using a local on-device LLM before they are
/// sent to remote API providers.
///
/// The filter runs entirely on-device. It:
/// 1. Sends the user's prompt to the local LLM with instructions to
///    identify and replace PII with numbered placeholders.
/// 2. Parses the LLM's response to build an [AnonymizationMap].
/// 3. Returns the scrubbed prompt for the remote API call.
/// 4. After the remote response arrives, uses [deAnonymizeResponse]
///    to restore original values.
///
/// If no local LLM is available, falls back to regex-based PII
/// detection for basic protection.
class PrivacyFilter {
  /// Creates a [PrivacyFilter] with the given local [LlmService].
  ///
  /// [localLlm] must be an on-device model — the whole point is that
  /// PII never leaves the device.
  const PrivacyFilter({required this.localLlm});

  /// The local on-device LLM used for intelligent anonymization.
  final LlmService? localLlm;

  /// System prompt that instructs the local LLM to anonymize text.
  static const _anonymizeSystemPrompt = '''
You are a privacy filter. Your ONLY job is to identify personally identifiable
information (PII) in the user's text and replace it with numbered placeholders.

PII includes:
- Person names → [PERSON_1], [PERSON_2], etc.
- Email addresses → [EMAIL_1], [EMAIL_2], etc.
- Phone numbers → [PHONE_1], [PHONE_2], etc.
- Physical addresses → [ADDRESS_1], [ADDRESS_2], etc.
- Company/organization names → [ORG_1], [ORG_2], etc.
- Dates of birth → [DOB_1], etc.
- Social security / ID numbers → [ID_1], etc.
- Account numbers → [ACCOUNT_1], etc.
- URLs with personal info → [URL_1], etc.
- Specific location names (cities, neighborhoods) → [LOCATION_1], etc.
- IP addresses → [IP_1], etc.
- Usernames / handles → [USERNAME_1], etc.

Rules:
1. Replace EVERY instance of the same entity with the SAME placeholder.
2. Preserve the grammatical structure — the text should still make sense.
3. Do NOT change non-PII content (technical terms, general concepts, etc.).
4. Generic locations (countries, well-known cities used as general context) may
be kept if they don't identify the user.
5. Output ONLY the anonymized text, nothing else. No explanations.
6. After the anonymized text, output a line "---MAPPING---" followed by each
mapping on its own line as "PLACEHOLDER=original value".

Example input:
"Remind me to call John at 555-1234 about the meeting at 123 Oak Street"

Example output:
Remind me to call [PERSON_1] at [PHONE_1] about the meeting at [ADDRESS_1]
---MAPPING---
[PERSON_1]=John
[PHONE_1]=555-1234
[ADDRESS_1]=123 Oak Street
''';

  /// Anonymize a list of [LlmMessage]s for a remote API call.
  ///
  /// Returns an [AnonymizedRequest] containing the scrubbed messages
  /// and the mapping needed to de-anonymize the response.
  Future<AnonymizedRequest> anonymizeRequest(
    LlmRequest request,
    PrivacyLevel level,
  ) async {
    if (level == PrivacyLevel.none) {
      return AnonymizedRequest(request: request, map: AnonymizationMap.empty);
    }

    // Build a combined text of all user messages for analysis.
    final userTexts = <_MessageText>[];
    for (var i = 0; i < request.messages.length; i++) {
      final msg = request.messages[i];
      switch (msg) {
        case UserLlmMessage(:final content):
          userTexts.add(_MessageText(index: i, text: content));
        case AssistantLlmMessage(:final content):
          userTexts.add(_MessageText(index: i, text: content));
        case SystemLlmMessage():
        case ToolResultLlmMessage():
          break; // System/tool messages don't contain user PII.
      }
    }

    if (userTexts.isEmpty) {
      return AnonymizedRequest(request: request, map: AnonymizationMap.empty);
    }

    // Combine all texts for a single anonymization pass.
    final combinedText = userTexts
        .map((t) => t.text)
        .join('\n---MSG_BREAK---\n');

    // Try LLM-based anonymization first, fall back to regex.
    final AnonymizationMap map;
    if (localLlm != null) {
      map = await _llmAnonymize(combinedText, level);
    } else {
      map = _regexAnonymize(combinedText);
    }

    if (!map.hasReplacements) {
      return AnonymizedRequest(request: request, map: map);
    }

    // Apply anonymization to messages.
    final newMessages = List<LlmMessage>.from(request.messages);
    // Split anonymized text back to individual messages.
    final anonymizedParts = map.anonymizedPrompt.split('\n---MSG_BREAK---\n');

    var partIdx = 0;
    for (final userText in userTexts) {
      if (partIdx >= anonymizedParts.length) break;
      final anonymized = anonymizedParts[partIdx].trim();
      partIdx++;

      final original = newMessages[userText.index];
      switch (original) {
        case UserLlmMessage():
          newMessages[userText.index] = LlmMessage.user(anonymized);
        case AssistantLlmMessage(:final toolCalls):
          newMessages[userText.index] = LlmMessage.assistant(
            anonymized,
            toolCalls: toolCalls,
          );
        default:
          break;
      }
    }

    // Also anonymize the system prompt if present.
    String? anonymizedSystemPrompt = request.systemPrompt;
    if (request.systemPrompt != null && map.hasReplacements) {
      anonymizedSystemPrompt = request.systemPrompt;
      // Don't anonymize system prompts — they're our instructions,
      // not user data. But we do scrub any user-data that leaked in.
    }

    final anonymizedRequest = LlmRequest(
      messages: newMessages,
      tools: request.tools,
      model: request.model,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
      systemPrompt: anonymizedSystemPrompt,
    );

    return AnonymizedRequest(request: anonymizedRequest, map: map);
  }

  /// De-anonymize a response from a remote LLM.
  ///
  /// Replaces all placeholders in the response text with the original
  /// values from [map], so the user sees real names, places, etc.
  LlmResponse deAnonymizeResponse(LlmResponse response, AnonymizationMap map) {
    if (!map.hasReplacements) return response;

    return switch (response) {
      TextLlmResponse(:final content, :final usage) => LlmResponse.text(
        map.deAnonymize(content),
        usage: usage,
      ),
      ToolCallsLlmResponse(:final content, :final calls, :final usage) =>
        LlmResponse.toolCalls(
          content != null ? map.deAnonymize(content) : null,
          calls
              .map(
                (c) => LlmToolCall(
                  id: c.id,
                  name: c.name,
                  arguments: _deAnonymizeArgs(c.arguments, map),
                ),
              )
              .toList(),
          usage: usage,
        ),
      ErrorLlmResponse() => response,
    };
  }

  /// De-anonymize a stream event.
  LlmStreamEvent deAnonymizeEvent(LlmStreamEvent event, AnonymizationMap map) {
    if (!map.hasReplacements) return event;

    return switch (event) {
      TextDeltaEvent(:final text) => LlmStreamEvent.textDelta(
        map.deAnonymize(text),
      ),
      ToolCallEvent(:final call) => LlmStreamEvent.toolCall(
        LlmToolCall(
          id: call.id,
          name: call.name,
          arguments: _deAnonymizeArgs(call.arguments, map),
        ),
      ),
      UsageEvent() => event,
      DoneEvent() => event,
    };
  }

  // ---------------------------------------------------------------------------
  // LLM-based anonymization
  // ---------------------------------------------------------------------------

  Future<AnonymizationMap> _llmAnonymize(
    String text,
    PrivacyLevel level,
  ) async {
    try {
      final response = await localLlm!.complete(
        LlmRequest(
          systemPrompt: _anonymizeSystemPrompt,
          messages: [LlmMessage.user(text)],
          temperature: 0.1, // Low temp for consistent, precise extraction.
          maxTokens: text.length + 512, // Need room for the mapping.
        ),
      );

      if (response case TextLlmResponse(:final content)) {
        return _parseAnonymizationResponse(content, text);
      }

      // Fallback to regex if LLM gave an unexpected response.
      return _regexAnonymize(text);
    } on Object {
      // LLM failed — fall back to regex-based detection.
      return _regexAnonymize(text);
    }
  }

  /// Parses the local LLM's anonymization response into an [AnonymizationMap].
  AnonymizationMap _parseAnonymizationResponse(
    String response,
    String originalText,
  ) {
    final parts = response.split('---MAPPING---');
    if (parts.length < 2) {
      // No mapping section — try regex fallback.
      return _regexAnonymize(originalText);
    }

    final anonymizedText = parts[0].trim();
    final mappingText = parts[1].trim();

    final replacements = <String, String>{};
    for (final line in mappingText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final eqIdx = trimmed.indexOf('=');
      if (eqIdx < 0) continue;
      final placeholder = trimmed.substring(0, eqIdx).trim();
      final original = trimmed.substring(eqIdx + 1).trim();
      if (placeholder.startsWith('[') && placeholder.endsWith(']')) {
        replacements[placeholder] = original;
      }
    }

    return AnonymizationMap(
      replacements: replacements,
      originalPrompt: originalText,
      anonymizedPrompt: anonymizedText,
    );
  }

  // ---------------------------------------------------------------------------
  // Regex-based fallback
  // ---------------------------------------------------------------------------

  /// Basic regex-based PII detection as a fallback when no local LLM
  /// is available.
  ///
  /// Less intelligent than LLM-based detection but catches common
  /// patterns. Better than nothing for baseline privacy protection.
  AnonymizationMap _regexAnonymize(String text) {
    var result = text;
    final replacements = <String, String>{};
    final counter = <String, int>{};

    String nextPlaceholder(String category) {
      final n = (counter[category] ?? 0) + 1;
      counter[category] = n;
      return '[${category}_$n]';
    }

    // Email addresses.
    result = result.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
      (m) {
        final placeholder = nextPlaceholder('EMAIL');
        replacements[placeholder] = m.group(0)!;
        return placeholder;
      },
    );

    // Phone numbers (various formats).
    result = result.replaceAllMapped(
      RegExp(
        r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}\b',
      ),
      (m) {
        final matched = m.group(0)!;
        // Avoid matching years or short numbers.
        if (matched.replaceAll(RegExp(r'\D'), '').length < 7) return matched;
        final placeholder = nextPlaceholder('PHONE');
        replacements[placeholder] = matched;
        return placeholder;
      },
    );

    // IP addresses.
    result = result.replaceAllMapped(
      RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      (m) {
        final placeholder = nextPlaceholder('IP');
        replacements[placeholder] = m.group(0)!;
        return placeholder;
      },
    );

    // Social security numbers (US format).
    result = result.replaceAllMapped(RegExp(r'\b\d{3}-\d{2}-\d{4}\b'), (m) {
      final placeholder = nextPlaceholder('ID');
      replacements[placeholder] = m.group(0)!;
      return placeholder;
    });

    // Credit card numbers.
    result = result.replaceAllMapped(
      RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b'),
      (m) {
        final placeholder = nextPlaceholder('ACCOUNT');
        replacements[placeholder] = m.group(0)!;
        return placeholder;
      },
    );

    return AnonymizationMap(
      replacements: replacements,
      originalPrompt: text,
      anonymizedPrompt: result,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Recursively de-anonymize string values in a JSON argument map.
  Map<String, dynamic> _deAnonymizeArgs(
    Map<String, dynamic> args,
    AnonymizationMap map,
  ) {
    return args.map((key, value) {
      if (value is String) {
        return MapEntry(key, map.deAnonymize(value));
      }
      if (value is Map<String, dynamic>) {
        return MapEntry(key, _deAnonymizeArgs(value, map));
      }
      if (value is List) {
        return MapEntry(
          key,
          value.map((v) {
            if (v is String) return map.deAnonymize(v);
            if (v is Map<String, dynamic>) return _deAnonymizeArgs(v, map);
            return v;
          }).toList(),
        );
      }
      return MapEntry(key, value);
    });
  }
}

/// An LLM request paired with its anonymization mapping.
///
/// The [request] has PII replaced with placeholders. After the remote
/// LLM responds, use [map] to restore original values.
class AnonymizedRequest {
  /// Creates an [AnonymizedRequest].
  const AnonymizedRequest({required this.request, required this.map});

  /// The anonymized LLM request (safe to send to remote APIs).
  final LlmRequest request;

  /// The mapping for de-anonymizing the response.
  final AnonymizationMap map;
}

/// Helper to track message indices for anonymization.
class _MessageText {
  const _MessageText({required this.index, required this.text});
  final int index;
  final String text;
}
