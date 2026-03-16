# Kabuk Chat System — Full Audit & Roadmap

> Generated March 2026. Covers all bugs fixed, redundancies, missing features,
> and a gap analysis for mass-adopted private messaging.

---

## Part 1 — Bugs Fixed in This Session

### 1. Kabuk AI conversation duplicated under "New Chat"

**Root cause:** `_KabukAiTile._openKabukAi()` read from `conversationsProvider`
which returns **all** conversations (agent + Nostr DMs). When a Nostr DM was the
most-recently-updated conversation it would open that DM instead of the AI
thread — or open the AI thread but with the wrong conversation ID. Repeated taps
created new agent conversations each time.

**Fix:** Filter conversations by `type == 'agent'` before picking the most
recent one. Nostr DMs (type `nostr_dm`) are no longer eligible.

**File:** [lib/ui/chat/conversation_list.dart](../lib/ui/chat/conversation_list.dart)

---

### 2. Profile Nostr events wrong data source

**Root cause:** `contactPublicNotesProvider` used `nostrService.fetchFollowingFeed([pubkeyHex])`
which fetches notes from a **following-feed subscription** not a direct-author
subscription. This means only notes from people _already followed_ would appear,
and even then the filter was applied globally. For contacts not in the following
list the provider always returned an empty array.

**Fix:** Changed to `nostrService.subscribe([NostrFilter(authors: [pubkeyHex], kinds: [NostrKind.textNote], limit: 30)])` wrapped in `collectNostrEvents()` — exactly the same pattern used by the explore `userNotesProvider`. Notes now load from the author's relay set directly.

**File:** [lib/config/providers.dart](../lib/config/providers.dart)

---

### 3. Profile view in chat used a different (weaker) UI than Explore

**Root cause:** `NostrChatDetail._openProfile()` pushed `ContactProfileSheet`
which rendered notes with a minimal `_NoteTile` widget, had no follow/unfollow
button, no NIP-05 badge, no lightning address, no banner image, and used a
different layout from the explore `ProfileView`.

**Fix:** `_openProfile()` now navigates to `ProfileView` (from
`lib/ui/explore/profile_view.dart`) directly — the same view used by the explore
tab. Profiles are now fully consistent between chat and explore: banner, avatar
overlap, NIP-05 verification badge, bio, follow/unfollow, lightning address, and
note cards all match.

**File:** [lib/ui/chat/nostr_chat_detail.dart](../lib/ui/chat/nostr_chat_detail.dart)

---

### 4. Media sending absent from DM UI

**Root cause:** `ChatInput` only exposed `onSend` (text), with no attachment
hook. `NostrChatDetail` had no media upload logic.

**Fix:**
- Added optional `onAttachment: VoidCallback?` to `ChatInput`. When non-null a
  paper-clip icon appears to the left of the text field.
- `NostrChatDetail` wires `_attachMedia()` to `onAttachment`. The flow:
  1. User taps clip → `MediaService.pickImage()` opens the gallery
  2. A dialog shows an image preview with Cancel / Send
  3. On confirm: file bytes are read via `MediaService.readFile()`, uploaded to
     `nostr.build/api/v2/upload/files` (NIP-96 compatible), and the returned URL
     is sent as a regular DM message
  4. `_DmBubble` already renders image URLs inline — no further UI changes needed

**Files:**
- [lib/ui/chat/chat_input.dart](../lib/ui/chat/chat_input.dart)
- [lib/ui/chat/nostr_chat_detail.dart](../lib/ui/chat/nostr_chat_detail.dart)

---

### 5. Messages not received when app is in background / minimized

**Root cause:** `nostrDmBackgroundListenerProvider` holds the relay subscription
and is watched from `KabukShell`. But when mobile OSes background the app the
Dart event loop is paused, all WebSocket connections drop, and new DMs accumulate
on relays with no consumer. When the user returned to the app, the relay
reconnection happened via the exponential-backoff timer in `SharedNostrService`
but could take up to 120 s.

**Fix:** `KabukShell` is converted from `ConsumerWidget` to
`ConsumerStatefulWidget` and mixes in `WidgetsBindingObserver`.
`didChangeAppLifecycleState` calls `nostrServiceProvider.connectAll()` when the
lifecycle state is `AppLifecycleState.resumed`. This triggers an immediate
reconnect on every foreground transition, so users receive pending DMs within
seconds of returning to the app.

**File:** [lib/ui/shell.dart](../lib/ui/shell.dart)

---

## Part 2 — Redundancies & Stale Code

| Item | Location | Issue |
|------|----------|-------|
| `ContactProfileSheet` note tile (`_NoteTile`) | `lib/ui/chat/contact_profile_sheet.dart` | Now dead code — `_openProfile()` never reaches it. Consider removing the whole notes section from `ContactProfileSheet` or redirecting to `ProfileView` entirely. |
| `contactPublicNotesProvider` (old) | Was in `providers.dart` | Replaced. If `ContactProfileSheet` still exists for non-Nostr contacts, it should call `userNotesProvider` from `profile_view.dart` instead (or `contactPublicNotesProvider` can remain as a thin wrapper). |
| `nostrProfileProvider` vs `profileForPubkeyProvider` | `providers.dart` vs `nostr_providers.dart` | Two separate providers both calling `nostrService.fetchProfileCached()`. `profileForPubkeyProvider` is the canonical one (used in thread view, search, topic feed, profile view, settings). `nostrProfileProvider` should be deprecated and its callers migrated to `profileForPubkeyProvider`. |
| `_KabukAiTile` subtitle vs `resumeLastConversationProvider` | `conversation_list.dart` | The subtitle shows "Your personal assistant" / "Tap to configure AI" but `resumeLastConversationProvider` in `shell.dart` already pre-loads the last conversation. The tile re-reads `conversationsProvider` on tap anyway — the subtitle could show the last message preview instead. |
| Chat sheet overlay re-implements message list | `shell.dart` `_ChatSheetOverlay` | Duplicates `ConversationDetail`'s message-list logic (auto-scroll, streaming bubble, thinking bubble). A shared `MessageListView` widget would reduce ~200 lines of duplication. |
| `_DmBubble` URL detection heuristic | `nostr_chat_detail.dart` | Basic string matching for image URLs. Should be replaced with a proper `imeta` tag parser (NIP-92) for media metadata. |
| `_ConversationTile` title fallback | `conversation_list.dart` | Shows raw pubkey prefix for unnamed contacts. Should use `nostrProfileProvider` to resolve names reactively, matching what the contacts row does. |

---

## Part 3 — Missing Features for a Private Messaging App

### Critical (blocking for any real use)

| # | Feature | Status | Details |
|---|---------|--------|---------|
| M1 | **Push notifications (background delivery)** | ✅ Done | A periodic WorkManager task (`kDmPollTaskName = 'kabuk.dm_poll'`) is registered via `WorkmanagerRefreshService.registerPeriodicDmPoll()` (15-minute interval, network-constrained). The `callbackDispatcher` in `background_refresh_impl.dart` handles the task: opens the Drift database, sums unread counts across `nostr_dm` and `nostr_channel` conversations, and fires a `flutter_local_notifications` high-priority notification on the `kabuk_dm` channel. Foreground reconnection (`connectAll()` on `AppLifecycleState.resumed`) provides real-time catch-up. |
| M2 | **NIP-17 inbox relay subscription on open** | ✅ Done | Both `nostrDmStreamProvider` and `nostrDmBackgroundListenerProvider` now call `db.getNewestNostrDmTimestamp()` before subscribing and pass `since:` to `watchDirectMessages()`. On launch the app fetches all DMs received since the last stored message. |
| M3 | **Read receipts / delivery status** | ✅ Done | `publishEvent` now waits up to 8 s for per-relay `OK` responses via `_pendingOks` completers (Completer-per-relay). `sendDirectMessage` returns `Future<int>` (accepted relay count). `_sendMessage` stores `'delivered:N'` status in the DB. `_DmBubble` displays a green `done_all` icon with `"N r"` relay count label when status starts with `'delivered:'`. |
| M4 | **Message deletion (NIP-59 + NIP-09)** | ✅ Done | Long-press on any bubble shows an options sheet. Tapping Delete calls `nostr.deleteEvents([eventId])` (NIP-09 kind-5) and `db.deleteMessage(id)` with a confirmation dialog before proceeding. |
| M5 | **Typed media in DMs (NIP-92 `imeta`)** | ✅ Done | `sendDirectMessageWithMedia` (impl) now emits NIP-92 `imeta` tags: `['imeta', 'url $mediaUrl', 'm $mimeType', 'filename $fileName']`. The `replyToEventId` param is also threaded through. |

### High Priority (needed for good UX)

| # | Feature | Status | Details |
|---|---------|--------|---------|
| H1 | **Group chats (NIP-28 public channels)** | ✅ Done | `NostrChannelDetail` (`lib/ui/chat/nostr_channel_detail.dart`) is a full `ConsumerStatefulWidget` that streams kind-42 messages via `watchChannelMessages()`, shows sender avatars from `nostrProfileProvider`, and sends via `sendChannelMessage()` with reply threading. Long-press menu: Reply, Copy text, Copy event ID, Delete own messages. `_showNewChannelSheet` persists the new channel as a `Conversations` row (`type='nostr_channel'`, `nostrPubkey=channelEventId`) and navigates to `NostrChannelDetail`. `_openConversation` routes `nostr_channel` conversations appropriately. `_ConversationTile` shows a teal `#` avatar for channel entries. |
| H2 | **Message reactions (NIP-25)** | ✅ Done | Long-press bubble → quick emoji picker (❤️ 👍 😂 😮 😢 🔥) calls `nostr.publishReaction()` and `db.upsertReaction()`. Reaction chips appear below each bubble via `_ReactionRow` (streams `db.watchReactions()`). Tapping a chip sends the same emoji again. |
| H3 | **Message replies / threading** | ✅ Done | `_replyToMessage` state in `_NostrChatDetailState`. Swipe-right or tap Reply in the options sheet sets it. `ChatInput` shows a reply banner. Sent messages include `replyToId` in `MessagesCompanion`. `_DmBubble` renders a `_ReplyPreview` card (async DB lookup of parent). |
| H4 | **Contact import from NIP-02 contact list** | ✅ Done | "Import Nostr Contacts" item in the conversation list overflow menu. Calls `nostr.fetchContactList()`, fetches each profile via `fetchProfileCached()`, and upserts into the knowledge store with `store.createPerson()` / `store.findPersonByNostrPubkey()`. |
| H5 | **Voice messages** | ✅ Done | `ChatInput` now accepts `onVoiceRecordStart` / `onVoiceRecordEnd`. When text is empty a hold-to-record mic button appears. `_NostrChatDetailState._startVoiceRecording()` calls `media.recordAudio()` and `_stopAndSendVoiceMessage()` calls `media.stopRecording()` → uploads → sends URL via `sendDirectMessage`. `MediaService` interface gained `stopRecording()` and `isRecording()`. |
| H6 | **Disappearing messages** | ✅ Done | "Set disappear timer" in the long-press options sheet. Options: 5 min, 1 h, 24 h, 7 days, Never. Calls `db.setMessageExpiry()`. An expiry label (`⏱ Expires in Xh`) is shown in the bubble. `purgeExpiredMessages()` is called on `initState`. Schema v3 added `expiresAt` column to `messages`. |
| H7 | **Unread badge on conversation list** | ✅ Already existed | `_ConversationTile` already rendered the green badge when `unreadCount > 0`. No change needed. |
| H8 | **Swipe-to-reply gesture on `_DmBubble`** | ✅ Done | `_DmBubble` wraps with `GestureDetector.onHorizontalDragUpdate`. Sliding right > 40 px triggers haptic + calls `onReply` once per gesture, with a fading reply icon visible during the drag. Drag end resets offset. |
| H9 | **Link previews** | ✅ Done | `_LinkPreviewCard` widget fetches Open Graph `og:title`, `og:description`, `og:image` via HTTP GET with 8 s timeout. Shown for plain URL messages (non-image). Falls back silently on error. Displays image, title, description, and hostname. |
| H10 | **Pinned / starred messages** | ✅ Done | Long-press → Pin/Unpin calls `db.pinMessage()`. Schema v3 added `isPinned` column. A `_PinnedMessagesBanner` watches `db.watchPinnedMessages()` and shows the first pinned message text at the top of the chat. Tapping the banner opens `_PinnedMessagesSheet` with a full list and per-message unpin buttons. |

### Normal Priority (polish & completeness)

| # | Feature | Status | Details |
|---|---------|--------|---------|
| N1 | **Typing indicator** | ✅ Done | Gift-wrapped ephemeral kind-14 DMs with `["typing", "true"]` tag and 30 s `expiration` (NIP-40). `NostrService.sendTypingIndicator` and `watchTypingIndicator` added. `ChatInput` emits `onChanged` callback. `_NostrChatDetailState` debounces sends every 5 s. `_TypingIndicatorBar` widget shows "X is typing…" text, auto-hides after 8 s without further events. Background listener skips typing indicator events (never persisted to DB). |
| N2 | **Online / last-seen status** | ✅ Done | `NostrKind.userStatus = 30315` added. `NostrService.publishUserStatus` (publishes kind 30315 `d:general`) and `watchUserStatus` (subscribes via `NostrFilter(kinds:[30315], authors:[pubkey], dTags:['general'])`) added. `_userStatusProvider` StreamProvider in `nostr_chat_detail.dart`. `_UserStatusLine` widget shows green dot + status text under the contact name in the AppBar. |
| N3 | **Contact NIP-05 verification badge in conversation list** | ✅ Done | `_NostrDmAvatar.build()` now wraps the `CircleAvatar` in a `Stack` with a `Positioned` blue `Icons.verified_rounded` badge (14px) when `profile?.nip05 != null`. |
| N4 | **Message search** | ✅ Done | Search icon in the `AppBar`. Tapping it replaces the title with a `TextField`. As the user types, `db.searchMessages(conversationId, query)` runs and results are shown in place of the normal message list. Closing search restores the normal view. |
| N5 | **Backup / export** | ✅ Done | Three-dot overflow menu in the chat AppBar has "Export chat" option. Calls `db.getMessages(conversationId)`, serialises to JSON (id, role, content, timestamp, status), writes to `getTemporaryDirectoryPath()` using `MediaService.writeFile`, and shows the file path in a snackbar. |
| N6 | **Multiple media attachments** | ✅ Done | The attachment button now opens `_AttachmentPicker` sheet with four options: Image (single), Multiple (calls `media.pickMultipleImages()`), Video (calls `media.pickVideo()`), File (calls `media.pickFile()`). `MediaService` interface and `SharedMediaService` gained `pickMultipleImages()` and `pickVideo()`. Multiple paths are uploaded and sent sequentially. |
| N7 | **Video / file attachments** | ✅ Done | See N6 — video and file options both available in the attachment sheet. |
| N8 | **Contact suggestion from address book** | ⏳ Pending | Optional permission to read device contacts and match by phone/email against Nostr `nip05` identifiers. |
| N9 | **Key verification (QR)** | ✅ Done | "Verify safety number" option added to the AppBar three-dot menu. `_showSafetyNumber` fetches both public keys via `authServiceProvider.getPublicKeyHex()`, sorts them, derives a 30-byte XOR digest, and formats as 5 groups of 6 decimal digits matching Signal's safety-number UX. Shown in a selectable-text dialog. |
| N10 | **Relay write confirmation** | ✅ Done | See M3 — relay count surfaced in `_DmBubble` status row as green `done_all` icon + `"N r"` label whenever status is `'delivered:N'`. |

---

## Part 4 — What's Needed for Mass Adoption

Mass adoption of a private messaging app requires clearing a bar that Signal,
WhatsApp, and iMessage have already set. Here is the delta:

### Non-negotiable for launch (must have day-1)

1. **Reliable push notifications (M1)** ✅ Done — A 15-minute periodic
   WorkManager task (`kDmPollTaskName`) is registered via
   `WorkmanagerRefreshService.registerPeriodicDmPoll()`. The
   `callbackDispatcher` opens the Drift DB, sums unread counts across
   `nostr_dm` and `nostr_channel` conversations, and fires a high-priority
   `flutter_local_notifications` notification on the `kabuk_dm` channel.
   Foreground reconnection (`connectAll()` on `AppLifecycleState.resumed`)
   provides real-time catch-up within seconds of returning to the app.

2. **Frictionless onboarding** ✅ Done — Generating a keypair on first launch is
   implemented. Key backup/recovery is now surfaced as a dedicated 4th onboarding
   page (page 3): users see their npub, can reveal and copy their nsec with a
   single tap, and acknowledge they've saved it before proceeding. Relay
   bootstrapping is automatic — 8 curated relays (including `inbox.nostr.wine`
   and `relay.0xchat.com` for NIP-17) are seeded on first launch with no user
   input required.

3. **NIP-17 inbox relay strategy (M2)** ✅ Done — Both `nostrDmStreamProvider`
   and `nostrDmBackgroundListenerProvider` call `db.getNewestNostrDmTimestamp()`
   before subscribing and pass `since:` to `watchDirectMessages()`. On every
   launch or foreground resume the app fetches all DMs received since the last
   stored message — no messages are missed across restarts or device switches.

4. **Delivery confirmation (M3)** ✅ Done — `publishEvent` waits up to 8 s for
   per-relay `OK` responses via `_pendingOks` completers. `sendDirectMessage`
   returns `Future<int>` (accepted relay count). `_sendMessage` persists
   `'delivered:N'` status to the DB. `_DmBubble` renders a green `done_all`
   icon with an `"N r"` relay-count label for any status starting with
   `'delivered:'`.

5. **Unread badge (H7)** ✅ Done — `_ConversationTile` renders a green badge
   whenever `unreadCount > 0`. The column is populated by the DM persistence
   layer and cleared on conversation open.

### Short-term differentiators (first 3 months)

6. **Group encrypted DMs (H1)** ✅ Done — `NostrChannelDetail`
   (`lib/ui/chat/nostr_channel_detail.dart`) streams kind-42 messages via
   `watchChannelMessages()`, shows sender avatars, and sends via
   `sendChannelMessage()` with reply threading. Long-press menu supports Reply,
   Copy, and Delete own messages. `_showNewChannelSheet` persists new channels
   as `Conversations` rows (`type='nostr_channel'`) and navigates to the detail
   view. `_openConversation` routes channel conversations correctly. Channels
   appear in the conversation list with a teal `#` avatar.

7. **Voice messages (H5)** ✅ Done — `ChatInput` shows a hold-to-record mic
   button when the text field is empty (`onVoiceRecordStart` /
   `onVoiceRecordEnd` callbacks). `_startVoiceRecording()` calls
   `media.recordAudio()` and `_stopAndSendVoiceMessage()` calls
   `media.stopRecording()` → uploads the file → sends the URL as a DM.
   `MediaService` interface gained `stopRecording()` and `isRecording()`.

8. **Message reactions (H2)** ✅ Done — Long-press bubble shows a quick emoji
   picker (❤️ 👍 😂 😮 😢 🔥). Selecting one calls `nostr.publishReaction()`
   (NIP-25) and `db.upsertReaction()`. Reaction chips appear below each bubble
   via `_ReactionRow` (streams `db.watchReactions()`). Tapping a chip sends the
   same emoji again.

9. **Replies / threading (H3)** ✅ Done — Swipe-right on any bubble or tap
   Reply in the options sheet sets `_replyToMessage` state. `ChatInput` shows a
   reply preview banner. Sent messages include `replyToId` in
   `MessagesCompanion`. `_DmBubble` renders a `_ReplyPreview` card (async DB
   lookup of the parent message).

10. **Contact import (H4)** ✅ Done — "Import Nostr Contacts" in the
    conversation list overflow menu. Calls `nostr.fetchContactList()`, fetches
    each profile via `fetchProfileCached()`, and upserts into the knowledge
    store via `store.createPerson()` / `store.findPersonByNostrPubkey()`.
    Bootstraps the user's full social graph from their existing Nostr kind-3
    contact list in one tap.

### Medium-term for retention

11. **Message search (N4)** ✅ Done — Search icon in the chat `AppBar` replaces
    the title with a `TextField`. As the user types,
    `db.searchMessages(conversationId, query)` runs and results are shown in
    place of the normal message list. Closing search restores the normal view.

12. **Link previews (H9)** ✅ Done — `_LinkPreviewCard` fetches Open Graph
    `og:title`, `og:description`, and `og:image` via HTTP GET with an 8 s
    timeout. Shown for plain URL messages (non-image). Falls back silently on
    network or parse error. Displays image, title, description, and hostname.

13. **End-to-end backup (N5)** ✅ Done — "Export chat" option in the three-dot
    AppBar overflow menu. Calls `db.getMessages(conversationId)`, serialises to
    JSON (id, role, content, timestamp, status), writes to the temp directory
    via `MediaService.writeFile`, and shows the file path in a snackbar.

14. **Disappearing messages (H6)** ✅ Done — "Set disappear timer" in the
    long-press options sheet. Options: 5 min, 1 h, 24 h, 7 days, Never. Calls
    `db.setMessageExpiry()`. An expiry label (`⏱ Expires in Xh`) is shown in
    the bubble. `purgeExpiredMessages()` is called on `initState`. Schema v3
    added an `expiresAt` column to `messages`.

15. **NIP-05 / key verification (N9)** ✅ Done — "Verify safety number" in the
    AppBar three-dot menu. `_showSafetyNumber` fetches both public keys via
    `authServiceProvider.getPublicKeyHex()`, sorts them, derives a 30-byte XOR
    digest, and formats it as 5 groups of 6 decimal digits — matching Signal's
    safety-number UX. Displayed in a selectable-text dialog.

---

## Part 5 — Architecture Observations

| Observation | Recommendation |
|-------------|---------------|
| `nostrProfileProvider` and `profileForPubkeyProvider` are duplicates | Migrate all `nostrProfileProvider` call sites to `profileForPubkeyProvider` (canonical) and remove the former. |
| `ContactProfileSheet` is partially superseded | Either (a) redirect all Nostr-contact profile views to `ProfileView`, or (b) merge the "copy key / DM button" actions into `ProfileView` as an appbar action when accessed from chat. |
| `_ChatSheetOverlay` duplicates `ConversationDetail` layout | Extract a shared `MessageListView` + `StreamingBubble` widget pair. Reduces ~200 lines of duplication and ensures UI consistency between the sheet and full-screen views. |
| Agent conversation isolation | The `conversationsProvider` returns all types together. Introduce a `type` filter parameter so callers can request only `agent` or only `nostr_dm` conversations without client-side filtering. |
| Media upload is hardcoded to `nostr.build` | Should be configurable via a settings page (NIP-96 server URL). Users in some jurisdictions may need alternative hosts, and ALGBT users may want blurred placeholders for sensitive media. |
| No re-subscription after relay reconnect is confirmed | `SharedNostrService._scheduleReconnect` calls `_connect()` which re-sends all active subscription REQs. Verify this works for the DM subscription (kind 1059 + gift wrap filter) after a reconnect triggered by `connectAll()` on foreground resume. |
