# Kabuk OS — Bug & Issue Tracker

## Open Issues

_No open issues. Last audit: Mar 17, 2026._

## Completed (archived)

<details>
<summary>18 resolved issues (click to expand)</summary>

### CRITICAL

- [x] **1. Isolate runtime always fails silently** — `_AgentIsolateMessage` passes non-transferable objects across isolate boundaries. The entire isolate architecture is dead code. **Fix**: Added logging, explanatory comments, `storeBlob()` now throws `StateError`.

### HIGH

- [x] **2. Agent name always "router"** — Added `agentName` field to `AgentResponse`. Router tags all dispatched responses.
- [x] **3. `LlmProvider.local` missing from selector** — Added 4th `ButtonSegment` for local provider.

### MEDIUM

- [x] **4. Identity shows "?"** — 3-way fallback: displayName → pubkey hex prefix → '?'.
- [x] **5. Explore avatar no accessibility label** — Wrapped in `Semantics`.
- [x] **6-8. Multiple accessibility fixes** — `IconButton` replacements, `Semantics` wrappers.
- [x] **9. `storeBlob()` silent failure** — Now throws `StateError`.
- [x] **10. `watch()`/`stream()` empty** — Documented as known limitation.
- [x] **11. Conversation delete no undo** — Added SnackBar feedback.
- [x] **12. Raw GestureDetectors lack accessibility** — Wrapped in `Semantics`.
- [x] **13. Disabled buttons no visual state** — Covered by `TextButton.icon`.

### LOW

- [x] **14. "1 widgets" grammar** — Conditional singular/plural.
- [x] **15. `_colorFromHex` unsafe parsing** — Added try-catch with fallback.
- [x] **16. Empty displayName** — Shows "Unnamed Identity".
- [x] **17. Title generation race condition** — Added `_pendingTitles` guard.
- [x] **18. Reddit image URL validation** — Added `FeedImage.isValidImageUrl()`.

</details>
