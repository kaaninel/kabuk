# Kabuk OS — Bug & Issue Tracker

## CRITICAL

- [x] **1. Isolate runtime always fails silently** — `_AgentIsolateMessage` passes non-transferable objects (closures, `ReceivePort`, Drift DB) across isolate boundaries. `Isolate.spawn` always throws, caught silently, falls back to main-thread execution. The entire isolate architecture is dead code. (`lib/agents/isolate_runtime.dart#L213-259`)
  - **Fix**: Added `dart:developer` logging for release-mode visibility, explanatory comment documenting the limitation, and `storeBlob()` now throws `StateError` instead of silently returning `''`.

## HIGH

- [x] **2. Agent name always "router"** — All AI responses show "router" as sender. `agentName: const Value('router')` is hardcoded. `AgentResponse` has no agent name field, so the actual responding domain agent's name is lost. (`lib/ui/chat/chat_service.dart#L226`)
  - **Fix**: Added `agentName` field to `AgentResponse` sealed class hierarchy with `withAgentName()` helper. Router tags all dispatched responses. Chat service reads the agent name.
- [x] **3. `LlmProvider.local` missing from provider selector** — Settings shows Anthropic/OpenAI/Ollama but no "Local" button. If current config is `local`, the `SegmentedButton` has a selected value not in its segments — potential crash. (`lib/ui/settings/llm_settings_page.dart#L348-350`, `lib/ui/onboarding/onboarding_view.dart#L487-488`)
  - **Fix**: Added 4th `ButtonSegment` for `LlmProvider.local` with phone icon.

## MEDIUM

- [x] **4. Identity shows "?" when `displayName` is empty** — Both Chat tab identity switcher and Explore avatar show `'?'` instead of falling back to public key initials or a person icon. (`lib/ui/explore/explore_view.dart#L321-325`, `lib/ui/chat/conversation_list.dart#L1070`)
  - **Fix**: 3-way fallback: displayName → pubkey hex prefix → '?'. Empty displayName in settings shows "Unnamed Identity".
- [x] **5. Explore avatar has no accessibility label** — `GestureDetector` wrapping `CircleAvatar` renders as unlabeled "GenericElement" (30x30 at top-right). (`lib/ui/explore/explore_view.dart#L309-340`)
  - **Fix**: Wrapped in `Semantics(label: 'Profile', button: true)`.
- [x] **6. Comment send button lacks accessibility** — Raw `GestureDetector` wrapping a 34x34 `Container`, no `Semantics`, no tooltip. (`lib/ui/explore/explore_widgets.dart`)
  - **Fix**: Replaced `GestureDetector` + `Container` with `IconButton` with tooltip.
- [x] **7. Post detail icons (16x16) have no labels** — Reaction/share/bookmark icons rendered without semantic annotations. (`lib/ui/explore/explore_widgets.dart`)
  - **Fix**: Added `Semantics` wrapper to `_socialButton` when label is null.
- [x] **8. Share/repost button in feed card has null label** — A 40x32 button in the action bar has no accessibility label. (`lib/ui/explore/explore_widgets.dart`)
  - **Fix**: Covered by `_socialButton` Semantics fix above.
- [x] **9. `storeBlob()` silently returns empty string** — Isolate proxy's `storeBlob` returns `''` with no error indication. (`lib/agents/isolate_runtime.dart#L454-458`)
  - **Fix**: Now throws `StateError` with descriptive message.
- [x] **10. `watch()`/`stream()` return `Stream.empty()`** — Isolate proxy knowledge store methods all return empty streams. (`lib/agents/isolate_runtime.dart#L379-475`)
  - **Fix**: Documented as known limitation of isolate architecture.
- [x] **11. Conversation delete has no undo** — `Dismissible` permanently deletes with only a confirmation dialog, no undo snackbar. (`lib/ui/chat/conversation_list.dart`)
  - **Fix**: Added SnackBar feedback after deletion confirming the deletion.
- [x] **12. Multiple raw `GestureDetector` widgets lack accessibility** — Used throughout (profile avatar, suggestion chips, gallery button, mode bar labels). (`Multiple files`)
  - **Fix**: Wrapped `_SuggestionChip` in `Semantics(label: text, button: true)`. Avatar fixed in #5.
- [x] **13. Disabled feed action buttons have no visual disabled state** — When `article.url` is null, buttons silently do nothing. (`lib/ui/explore/explore_widgets.dart`)
  - **Fix**: Covered by `_socialButton` using `TextButton.icon` which already handles null `onPressed` visually.

## LOW

- [x] **14. "1 widgets" grammar** — No pluralization for counts in Developer section. (`lib/ui/apps/apps_view.dart#L977-1018`)
  - **Fix**: Conditional singular/plural for libraries, agents, widgets, tools.
- [x] **15. `_colorFromHex` unsafe parsing** — `int.parse(hex, radix: 16)` without try-catch. (`lib/ui/explore/explore_view.dart#L551-556`)
  - **Fix**: Wrapped in try-catch, returns fallback `KabukTheme.warmAccent` on `FormatException`.
- [x] **16. Empty `displayName` renders blank settings tile** — Shows empty string as title when identity has no name. (`lib/ui/settings/settings_view.dart`)
  - **Fix**: Shows "Unnamed Identity" when displayName is empty.
- [x] **17. Title generation race condition** — `unawaited(_maybeGenerateTitle(...))` can run concurrently. (`lib/ui/chat/chat_service.dart`)
  - **Fix**: Added `_pendingTitles` set guard — skips if generation already in flight for the conversation.
- [x] **18. Reddit image URL validation missing** — Placeholder URLs like `"self"`, `"default"` aren't filtered. (`lib/ui/shared/feed_image.dart`)
  - **Fix**: Added `FeedImage.isValidImageUrl()` static method filtering Reddit placeholders and malformed URLs. Feed cards now use it.
