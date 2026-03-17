# Kabuk Chat — Implementation Plan (Nostr-Native)

**Date:** 2026-02-26  
**Goal:** Make Kabuk's chat a daily-driver messaging platform built entirely on Nostr. Zero onboarding friction — you already have an identity.

---

## Philosophy

Every Kabuk user already has a secp256k1 keypair. That **is** their Nostr identity. No account to create, no server to pick, no password to remember. Open the app, go to Chat, and you can message anyone on the Nostr network — Damus, Primal, Amethyst, or any other Nostr client.

Matrix is being removed entirely. One protocol, one identity, one contact list.

---

## 1. Current State — What Exists Today

### Agent Chat (Local AI) ✓
- Send text / get AI response with streaming
- Conversation list with auto-generated titles
- Delete conversations (swipe or drawer), delete individual messages
- Tool call/result display, RFW widget rendering in-chat
- Markdown rendering + input toolbar

### Nostr Infrastructure ✓
- `NostrService` — full NIP-01 event model, relay management, subscriptions
- `SharedNostrService` — signing (NIP-01), relay WebSocket connections, auto-reconnect
- `AuthService` — secp256k1 keypair generation, signing, verification
- Social features — reactions (NIP-25), replies (NIP-10), reposts (NIP-18)
- Contact list — `fetchContactList()` reads kind 3 events (NIP-02)
- Profile metadata — `fetchProfile()` / `publishMetadata()` (kind 0)
- `NostrKind.encryptedDM = 4` defined (NIP-04, legacy)
- Relay config persistence in knowledge store

### Matrix (To Be Removed)
- `lib/services/matrix.dart` — interface
- `lib/platform/shared/matrix_service_impl.dart` — implementation
- `lib/ui/chat/matrix_chat_detail.dart` — chat view
- Matrix providers in `providers.dart`
- Matrix SDK dependency in `pubspec.yaml`
- Matrix settings page in `settings_view.dart`
- References in `conversation_list.dart`

### What's Broken / Missing
- **No Nostr DMs** — `NostrKind.encryptedDM` is defined but NIP-04 / NIP-17 / NIP-44 are not implemented
- **Contacts are decorative** — `schema:Person` entities have no pubkey, can't message them
- **Two separate incompatible chat lists** — Agent and Matrix tiles side by side
- **No media messages** — Text only in all chat views
- **No chat management** — No pin, archive, mute, search
- **No notifications** — Messages arrive silently

---

## 2. Architecture Decision: NIP-17 Gift-Wrapped DMs

### Why NIP-17 + NIP-44, Not NIP-04

NIP-04 (kind 4) is the legacy encrypted DM standard. It leaks metadata — any relay can see who talks to whom and when. Only the content is encrypted.

NIP-17 + NIP-44 (the modern standard) fixes this:

1. **Sender creates the real message** — a kind 14 `dm` event, encrypted with NIP-44 (XChaCha20-Poly1305 + HKDF-SHA256) using the shared secret between sender and recipient.
2. **Sender wraps it in a Gift Wrap** — a kind 1059 `gift-wrap` event signed by a **random throwaway keypair** and encrypted to the recipient's pubkey. The relay sees a random sender, not the real one.
3. **Sender also wraps a copy for themselves** — same gift wrap, but encrypted to their own pubkey, so they can read their own sent messages.
4. **Recipient unwraps** — decrypts the kind 1059 outer layer, then decrypts the kind 14 inner content.

This is what Damus, Primal, and Amethyst use now. Any message sent from Kabuk will be readable in those clients and vice versa.

### NIP-44 Encryption Flow

```
Sender keypair:    privA, pubA
Recipient keypair: privB, pubB

Shared secret = ECDH(privA, pubB) = ECDH(privB, pubA)
Conversation key = HKDF-SHA256(shared_secret, salt=random_32_bytes)
Encrypted payload = XChaCha20-Poly1305(plaintext, key=conversation_key, nonce=random_24_bytes)

Output: base64(version_byte + salt + nonce + ciphertext + mac)
```

### Event Structure

```json
// Kind 14 — the actual DM (before wrapping)
{
  "kind": 14,
  "created_at": 1234567890,
  "tags": [["p", "<recipient_pubkey>"]],
  "content": "Hey, how's it going?"
}

// Kind 13 — a Seal (kind 14 encrypted to receiver, signed by real sender)
{
  "kind": 13,
  "pubkey": "<sender_real_pubkey>",
  "content": "<nip44_encrypted(kind_14_json)>",
  "tags": []
}

// Kind 1059 — the Gift Wrap (kind 13 encrypted to receiver, signed by throwaway key)
{
  "kind": 1059,
  "pubkey": "<random_throwaway_pubkey>",
  "content": "<nip44_encrypted(kind_13_json)>",
  "tags": [["p", "<recipient_pubkey>"]]
}
```

### Storage

Nostr DMs are stored locally in the Drift database after decryption. The relay only stores gift-wrapped events. On a new device, the user reconnects to relays and re-fetches their gift wraps to reconstruct conversation history.

**All DM messages live in the `Messages` table** alongside agent chat messages. The `Conversations` table gets a `type` column (`agent` or `nostr_dm`) and a `nostrPubkey` column for human chats.

---

## 3. Implementation Plan

### Sprint 1 — NIP-44 Encryption + NIP-17 Gift Wraps

**Goal:** Send and receive encrypted DMs that are compatible with Damus/Primal/Amethyst.

#### 1a. NIP-44 Encryption/Decryption

Implement in `lib/services/nip44.dart`:

```dart
abstract final class Nip44 {
  /// Encrypts plaintext using NIP-44 v2 (XChaCha20-Poly1305 + HKDF).
  static String encrypt(String plaintext, Uint8List conversationKey);
  
  /// Decrypts a NIP-44 payload.
  static String decrypt(String payload, Uint8List conversationKey);
  
  /// Derives a conversation key from our privkey and their pubkey via ECDH + HKDF.
  static Uint8List deriveConversationKey(Uint8List privateKey, Uint8List publicKey);
}
```

Dependencies already available:
- `pointycastle` — already in pubspec (used by nostr_service_impl.dart for SHA-256)
- Need to add ECDH shared secret (secp256k1 point multiplication) + HKDF-SHA256 + XChaCha20-Poly1305
- Consider `cryptography` package for XChaCha20-Poly1305 (pointycastle may not have it)

Key implementation details:
- NIP-44 uses **version byte 2** as the first byte of the payload
- Salt is 32 random bytes, nonce is 24 random bytes (generated per message)
- Content is padded before encryption to hide message length
- Padding: round up to the next power-of-2 boundary (min 32 bytes, max 65535)

#### 1b. Gift Wrap (NIP-17) Logic

Add to `NostrService` interface and `SharedNostrService`:

```dart
/// Sends a NIP-17 gift-wrapped DM to [recipientPubkey].
Future<void> sendDirectMessage(String recipientPubkey, String content);

/// Subscribes to incoming gift-wrapped DMs (kind 1059) for the current user.
Stream<NostrDm> watchDirectMessages();

/// Decrypts a kind 1059 gift wrap into its inner kind 14 DM.
Future<NostrDm?> unwrapGiftWrap(NostrEvent giftWrap);
```

The flow for **sending**:
1. Create kind 14 event with DM content + `["p", recipientPubkey]` tag
2. Encrypt kind 14 with NIP-44 using sender privkey + recipient pubkey → kind 13 Seal, signed by sender
3. Generate random throwaway keypair
4. Encrypt kind 13 with NIP-44 using throwaway privkey + recipient pubkey → kind 1059 Gift Wrap
5. Publish kind 1059 to relays
6. Repeat step 3-5 but encrypt to **sender's own pubkey** (so we can read our own messages)

The flow for **receiving**:
1. Subscribe to kind 1059 events where `["p", myPubkey]`
2. Decrypt outer layer (kind 1059 → kind 13) using my privkey + throwaway pubkey
3. Decrypt inner layer (kind 13 → kind 14) using my privkey + sender pubkey
4. Extract content, sender, and timestamp from the kind 14 event

#### 1c. Nostr DM Data Types

```dart
/// A decrypted Nostr DM message.
class NostrDm {
  final String id;              // Inner event ID
  final String senderPubkey;    // Real sender
  final String recipientPubkey; // Real recipient
  final String content;         // Decrypted plaintext
  final DateTime timestamp;
  final bool isOwnMessage;
}
```

**Files to create:**
- `lib/services/nip44.dart` — NIP-44 v2 encrypt/decrypt/deriveKey
- `lib/services/nip17.dart` — Gift wrap/unwrap, DM send/receive types

**Files to modify:**
- `lib/services/nostr.dart` — Add DM methods and `NostrDm` type, add kind 13/14/1059 to `NostrKind`
- `lib/platform/shared/nostr_service_impl.dart` — Implement send/receive DMs
- `lib/services/auth.dart` — Add `getPrivateKeyBytes()` for ECDH (currently only hex export)

---

### Sprint 2 — Contacts That Work

**Goal:** Your Nostr follow list IS your contact list. Add someone → follow them → message them.

#### 2a. Contact Model = Nostr Pubkey

Upgrade `PersonData` with a `nostrPubkey` field:
- New predicate: `kabuk:nostrPubkey` on `schema:Person` entities.
- `PersonData.fromTriples()` extracts it.
- `createPerson()` accepts optional `nostrPubkey`.

Nostr's follow list (kind 3) becomes the primary contact source:
- On app start, `fetchContactList()` returns followed pubkeys.
- For each pubkey, `fetchProfile()` gets their name + avatar.
- Sync: Nostr kind 3 → `schema:Person` entities in the knowledge store.
- Adding a contact in Kabuk also publishes an updated kind 3 event to relays.

#### 2b. New Contact Flow

Replace the "Add Contact" bottom sheet:

**Option A — Add by npub / Nostr ID:**
- User types or pastes an npub (bech32) or hex pubkey.
- App fetches their profile (kind 0) for display name + avatar.
- On confirm: creates `schema:Person` with `kabuk:nostrPubkey`, adds to kind 3 follow list.

**Option B — Add by NIP-05 identifier:**
- User types `alice@nostr.com` (NIP-05 address).
- App resolves via `https://nostr.com/.well-known/nostr.json?name=alice` to get the pubkey.
- Validate the pubkey matches, show profile, confirm.

**Option C — Scan QR Code:**
- Scan someone's npub QR code (standard in Damus/Primal).
- Parse bech32 → hex pubkey → fetch profile → confirm.

**Option D — Share invite link:**
- Generate a link: `https://kabuk.app/u/npub1...` or just display the npub as a QR.
- Other Nostr users can scan this in any client.

#### 2c. Contact Tap → DM

Replace `_ContactAvatar.onTap`:
- If contact has `kabuk:nostrPubkey`: open or create DM conversation with that pubkey.
- If no pubkey: show contact detail with "Add their Nostr ID" option.
- Remove the Matrix ID / email hack entirely.

#### 2d. Contact Sync

Bidirectional sync between knowledge store and Nostr kind 3:
- **Pull:** On startup and periodically, fetch kind 3 → update/create `schema:Person` entities.
- **Push:** When user adds/removes contact in Kabuk, publish updated kind 3 event.
- Conflict resolution: latest timestamp wins (standard Nostr replaceable event behavior).
- Profile data (kind 0) is cached locally but refreshed periodically.

**Files to modify:**
- `lib/knowledge/types/person.dart` — Add `nostrPubkey` field
- `lib/config/namespaces.dart` — Add `kabukNostrPubkey` predicate
- `lib/ui/chat/conversation_list.dart` — Replace contact flow + tap logic
- `lib/platform/shared/nostr_service_impl.dart` — Add NIP-05 resolution

---

### Sprint 3 — Unified Chat List & DM View

**Goal:** One list showing all chats (AI + Nostr DMs), with a proper DM detail view.

#### 3a. Database Schema v2

Add columns to `Conversations` table and bump schema version:

```sql
ALTER TABLE conversations ADD COLUMN type TEXT NOT NULL DEFAULT 'agent';
ALTER TABLE conversations ADD COLUMN nostr_pubkey TEXT;
ALTER TABLE conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE conversations ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;
ALTER TABLE conversations ADD COLUMN is_muted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE conversations ADD COLUMN unread_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE conversations ADD COLUMN last_message TEXT;
ALTER TABLE conversations ADD COLUMN last_message_at INTEGER;
```

Add columns to `Messages` table:

```sql
ALTER TABLE messages ADD COLUMN nostr_event_id TEXT;
ALTER TABLE messages ADD COLUMN status TEXT NOT NULL DEFAULT 'sent';
ALTER TABLE messages ADD COLUMN reply_to_id TEXT;
```

Conversation `type` values: `agent`, `nostr_dm`, `nostr_group` (future).

#### 3b. Nostr DM Chat Detail View

Replace `matrix_chat_detail.dart` with `nostr_chat_detail.dart`:
- Same UI structure as the existing Matrix chat view (message list + input).
- Messages come from two sources merged by timestamp:
  1. Locally stored messages in Drift `Messages` table (fast, offline)
  2. Incoming DMs from the relay subscription (real-time)
- On first open of a DM: fetch historical gift wraps from relays for that pubkey, decrypt, store locally.
- Subsequent opens: read from Drift, listen for new relay events.

#### 3c. Unified Chat List

Replace the current triple-list (`_ContactsRow` + `_MatrixRoomTile` + `_ConversationTile`) with a single sorted list:

```dart
sealed class ChatItem {
  DateTime get lastActivity;
  String get displayTitle;
  String? get lastMessage;
  int get unreadCount;
}

class AgentChatItem extends ChatItem { ... }
class NostrDmChatItem extends ChatItem { ... }
```

Riverpod provider merges agent conversations + Nostr DM conversations from the same `Conversations` table, sorted by `last_message_at DESC`. The Kabuk AI tile stays pinned at the top.

#### 3d. Chat Management Actions

Long-press any chat tile → bottom sheet:
- **Pin** / **Unpin** — `is_pinned` toggle
- **Mute** / **Unmute** — `is_muted` toggle
- **Archive** — `is_archived` toggle, hidden from main list
- **Delete** — Delete conversation + messages from local DB
- **Mark as read** — Reset `unread_count` to 0
- For Nostr DMs additionally: **Block** — add pubkey to local block list, ignore future messages

#### 3e. Chat Search

Search icon in app bar → search overlay:
- Full-text search across `Messages.content` in Drift (FTS5 virtual table or LIKE query).
- Results grouped by conversation with message previews.
- Tapping a result opens the conversation scrolled to that message.

**Files to create:**
- `lib/ui/chat/nostr_chat_detail.dart` — Nostr DM chat view

**Files to modify:**
- `lib/knowledge/database.dart` — Schema v2 migration
- `lib/ui/chat/conversation_list.dart` — Unified list, long-press actions, search
- `lib/config/providers.dart` — Unified conversation + message providers, remove Matrix providers
- `lib/ui/chat/chat_service.dart` — Route to Nostr or Agent based on conversation type

---

### Sprint 4 — Remove Matrix Entirely

**Goal:** Clean removal of all Matrix code and dependencies.

#### 4a. Files to Delete

- `lib/services/matrix.dart`
- `lib/platform/shared/matrix_service_impl.dart`
- `lib/ui/chat/matrix_chat_detail.dart`

#### 4b. Files to Edit

- `lib/config/providers.dart` — Remove all `matrix*` providers, imports, `SharedMatrixService`
- `lib/ui/chat/conversation_list.dart` — Remove `_MatrixRoomTile`, Matrix room imports
- `lib/ui/settings/settings_view.dart` — Remove `_MatrixSettingsPage` and Matrix section
- `pubspec.yaml` — Remove `matrix: ^0.40.2` and `sqflite` (if only used by Matrix)

#### 4c. Why Sprint 4 (not Sprint 1)

Matrix removal happens **after** the Nostr DM system is working, not before. This way:
- Chat never stops working during the transition
- Can A/B compare Matrix vs Nostr conversations during development
- If something goes wrong with NIP-17, Matrix is still there as fallback
- Clean removal after Nostr is proven solid

---

### Sprint 5 — Core Messaging Features

**Goal:** Media, replies, reactions — everything people use daily.

#### 5a. Media Messages

**Photos/files via NIP-94 (File Metadata) + NIP-96 (HTTP File Storage):**

Nostr doesn't have built-in file hosting like Matrix. Options:
1. **NIP-96 media servers** — Upload to a public media host (nostr.build, void.cat, etc.). Get back a URL. Include the URL in the DM content.
2. **Inline base64** — For small files, encode directly in the event content (not recommended for large media).
3. **NIP-94 file metadata** — Kind 1063 events describe uploaded files with URL, hash, dimensions, etc.

Recommended approach:
- Upload media to a NIP-96 server using HTTP POST.
- Include the resulting URL in the kind 14 DM content.
- Parse URLs in received messages and render as image/file/audio previews.
- Media is E2E encrypted before upload (encrypt with conversation key, upload encrypted blob, send URL + key in DM).

**Send photos/videos:**
- Camera button in chat input (already have `image_picker`).
- Upload to NIP-96 server → get URL → send in DM.
- Media bubble widget: thumbnail preview, tap to full-screen.

**Voice messages:**
- Hold-to-record (already have `record` dependency).
- Upload audio to NIP-96 → send URL in DM.
- Voice bubble: play button + waveform + duration.

#### 5b. Reply

- Long-press message → "Reply".
- Kind 14 includes `["e", "<replied_event_id>", "", "reply"]` tag.
- Shows reply preview bar above input and quoted message in bubble.
- For agent chat: include reply context in agent message history.

#### 5c. Reactions (NIP-25)

Already implemented in `NostrService` for social posts. Extend to DMs:
- Double-tap or long-press → quick reaction (6 emoji).
- For DMs: publish a kind 7 reaction referencing the inner kind 14 event ID.
- Gift-wrap the reaction the same way as a DM (privacy).
- Display as emoji chips below the message bubble.

#### 5d. Link Previews

- Detect URLs in messages.
- Fetch Open Graph metadata (title, description, image).
- Render as a card below the message text.
- Cache metadata in Drift to avoid re-fetching.

**Files to modify:**
- `lib/ui/chat/chat_input.dart` — Media/file/voice buttons, reply preview bar
- `lib/ui/chat/message_bubble.dart` — Media bubbles, reactions, reply quotes, link previews
- `lib/ui/chat/nostr_chat_detail.dart` — Reply state
- `lib/services/nostr.dart` — Add media upload methods
- `lib/platform/shared/nostr_service_impl.dart` — NIP-96 upload implementation

---

### Sprint 6 — Groups (NIP-17 Group DMs + NIP-29)

**Goal:** Group chats for family, friends, teams.

#### 6a. NIP-17 Group DMs (Simple)

For small groups (≤20 people), NIP-17 supports multi-party DMs:
- Kind 14 includes multiple `["p", pubkey]` tags (one per recipient).
- Gift wrap is sent to **each** recipient individually.
- Each participant decrypts independently.
- Simple but doesn't scale — N messages × M recipients = N×M gift wraps.

#### 6b. NIP-29 Relay-Based Groups (Later)

For larger groups:
- Groups live on a specific relay that enforces membership.
- Kind 9 (group chat message), kind 9000-9030 (admin events).
- The relay acts as the "server" — validates membership before relaying.
- More complex to implement but scales better.

**Recommended path:** Start with NIP-17 group DMs (simple, compatible with Damus/Primal), add NIP-29 later for larger communities.

#### 6c. Create Group

- "New Group" option in chat list.
- Multi-select contacts → set group name → create.
- Under the hood: creates a local conversation with type `nostr_group`, stores member pubkeys.
- First message sends gift wraps to all members.

#### 6d. Group Info

- Group name, member list, admin controls.
- Add/remove members.
- Leave group.

---

### Sprint 7 — Notifications & Reliability

**Goal:** Messages arrive reliably and notify you.

#### 7a. Push Notifications

Nostr doesn't have a native push system. Options:
- **NIP-72-style push gateways** — A service that monitors relays for your gift wraps and sends FCM/APNs pushes.
- **Self-hosted notification relay** — Run a relay that forwards to push.
- **ntfy.sh** — Open-source push service, subscribe to a topic derived from your pubkey.

Recommended: Use a NIP-72 push gateway or ntfy.sh initially, self-host later.

Packages: `flutter_local_notifications`, `firebase_messaging` (for FCM).

#### 7b. Local Notifications

- When app is in foreground but chat is not visible: local notification.
- `flutter_local_notifications` for heads-up display.
- Notification grouping by conversation.

#### 7c. Background Relay Connection

- **Android:** `WorkManager` or foreground service to keep WebSocket alive.
- **iOS:** Background App Refresh — reconnect to relays, fetch pending gift wraps.
- Reconnection is already handled by `SharedNostrService._scheduleReconnect()`.

#### 7d. Offline Message Queue

- When sending fails (no relay connection), store message locally with `status: queued`.
- Show a clock icon on the message bubble.
- On relay reconnect, flush the queue.
- Update `status` to `sent` after relay acknowledges (OK message).

---

### Sprint 8 — Polish & Daily-Driver Quality

**Goal:** The small things that make you not miss WhatsApp.

- **Message deletion** — Kind 5 (NIP-09) event deletes a message. Gift-wrap the deletion event.
- **Starred/saved messages** — Bookmark messages locally, viewable in a separate list.
- **Chat export** — Export conversation as text/JSON.
- **User profile** — Name, avatar, about text, NIP-05 address. Publish as kind 0.
- **Contact verification** — Show NIP-05 verified badge next to contacts.
- **Chat wallpapers** — Per-conversation background image.
- **Notification sounds** — Custom sounds per conversation.
- **Accessibility** — Screen reader labels, large text support, high contrast.
- **Multi-device sync** — Same keypair on multiple devices. Gift wraps are inherently multi-device (all copies encrypted to your pubkey are fetchable from any device).

---

## 4. Priority Order

| # | Sprint | What You Get | Time Est. |
|---|--------|-------------|-----------|
| 1 | NIP-44 + NIP-17 DMs | Send/receive encrypted DMs compatible with Damus/Primal | 2 weeks |
| 2 | Contacts That Work | Nostr follow list = contacts, add by npub/NIP-05/QR, contact → DM | 1.5 weeks |
| 3 | Unified List & DM View | One chat list, DM detail view, pin/mute/archive/search | 2 weeks |
| 4 | Remove Matrix | Clean deletion of Matrix code + SDK dependency | 0.5 weeks |
| 5 | Core Messaging | Photos, files, voice (NIP-96), reply, reactions, link previews | 2.5 weeks |
| 6 | Groups | NIP-17 group DMs, create/manage groups | 2 weeks |
| 7 | Notifications | Push gateway, local notifications, background sync, offline queue | 2 weeks |
| 8 | Polish | Delete for everyone, profiles, NIP-05, starred, export | 1.5 weeks |

**To stop missing WhatsApp:** Sprints 1-5 (≈ 8.5 weeks).  
**To genuinely replace it:** Sprints 1-7 (≈ 12.5 weeks).  
**Full polish:** Sprints 1-8 (≈ 14 weeks).

---

## 5. Technical Decisions

### Why Nostr (not Matrix)

| Dimension | Nostr | Matrix |
|-----------|-------|--------|
| **Account** | Already have it (secp256k1 keypair) | Requires separate registration |
| **Onboarding** | Zero — identity exists | Full onboarding flow needed |
| **Protocol** | Same protocol as social feed | Separate protocol from everything else |
| **Contact list** | Kind 3 follow list, shared with social | Separate contact system |
| **Interoperability** | Damus, Primal, Amethyst, 0xchat | Element, FluffyChat |
| **Metadata privacy** | Excellent with NIP-17 gift wraps | Server sees metadata |
| **Encryption** | NIP-44 (XChaCha20-Poly1305) | Olm/Megolm |
| **Infrastructure** | Public relays, no account needed | Need a homeserver |
| **Server dependency** | None — any relay works | Locked to one homeserver |
| **Self-hosting** | Run `strfry` in 5 minutes | Run Synapse (heavy) |
| **Identity** | Portable keypair, own your identity | Server-assigned, server-dependent |

### What We Trade Away
- **Typing indicators** — Nostr doesn't have them (by design — privacy). We can simulate locally for agent chat.
- **Read receipts** — Same reason. We can show sent/delivered states based on relay OKs.
- **Reliable delivery** — Relays are best-effort. Mitigated by: using multiple relays, offline queue, retry logic.
- **Media hosting** — No built-in file storage. NIP-96 servers fill this gap.
- **Mature group chat** — NIP-29 is newer than Matrix rooms. Start with NIP-17 group DMs which are simpler.

### What We Gain
- **Zero onboarding** — The biggest win. No "Sign up for Matrix" friction.
- **One identity everywhere** — Social + chat + payments (NIP-57 zaps) all use the same keypair.
- **True portability** — Switch clients freely. Your messages are on relays, not locked in a server.
- **Follow list = contacts** — No duplicate contact systems.
- **Privacy by default** — Gift wraps hide metadata from relays.

### Storage Architecture

```
┌─────────────────────────────────┐
│ Drift/SQLite (KabukDatabase)    │
│                                 │
│  Conversations ← agent + nostr  │
│  Messages ← agent + decrypted   │
│  Triples ← knowledge store      │
│                                 │
│  Everything in one DB.           │
│  No separate Matrix SDK DB.     │
└─────────────────────────────────┘
         ↑ decrypt + store
┌─────────────────────────────────┐
│ Nostr Relays (WebSocket)        │
│                                 │
│  Kind 1059 gift wraps ← DMs    │
│  Kind 0 metadata ← profiles    │
│  Kind 3 contacts ← follow list │
│  Kind 1 notes ← social feed    │
│                                 │
│  Encrypted at rest on relay.    │
│  Only recipient can decrypt.    │
└─────────────────────────────────┘
```

All human messages are stored decrypted in the local Drift DB after unwrapping. The relay only ever has encrypted gift wraps. This is simpler than the Matrix dual-database approach — one DB for everything.

---

## 6. Dependencies

### Already in pubspec (no changes needed)
- `pointycastle` — SHA-256, secp256k1 (used by nostr_service_impl)
- `web_socket_channel` — Nostr relay connections
- `image_picker` — Photo/video capture
- `record` — Voice recording
- `url_launcher` — Opening links
- `video_player` — Video playback
- `cached_network_image` — Image caching

### To add
```yaml
# NIP-44 encryption (XChaCha20-Poly1305)
cryptography: ^2.7.0

# Push notifications
flutter_local_notifications: ^18.0.0

# QR code scanning (contact add)
mobile_scanner: ^6.0.0

# QR code generation (share npub)
qr_flutter: ^4.1.0

# Bech32 encoding (npub/nsec/nprofile)
bech32: ^0.2.2

# Background processing
workmanager: ^0.5.0
```

### To remove
```yaml
# Matrix SDK and its dependencies
matrix: ^0.40.2
sqflite: ^2.4.2  # if only used by Matrix
```

---

## 7. What Kabuk Has That WhatsApp Never Will

| Feature | Why It Matters |
|---------|---------------|
| **AI agents in every conversation** | Summarize, translate, draft replies, search your data |
| **Dynamic UI widgets in chat** | Agents render interactive cards, forms, charts |
| **No phone number, no email, no account** | Identity is a keypair. True pseudonymity. |
| **Portable identity** | Your keypair works in Damus, Primal, Amethyst, Kabuk — move freely |
| **Follow list = contacts** | One contact list across social + messaging |
| **Knowledge store** | Every contact, message, and piece of data in a queryable RDF graph |
| **Offline-first** | Everything works without internet. Sync when you reconnect. |
| **Open protocol** | Nostr is a protocol, not a platform. No vendor lock-in. |
| **Gift-wrap privacy** | Relays can't see who you're talking to |
| **Agents can message for you** | Schedule sends, auto-replies, smart notifications |
| **Data stays on your device** | Encrypted at rest. Relays only see encrypted blobs. |
| **Zaps** | Bitcoin tips via NIP-57 — built into the identity. WhatsApp wishes. |

The agent runtime, RFW rendering, knowledge store, Nostr relay management, and secp256k1 identity **already exist** in the codebase. This plan wires them together into a complete chat experience with zero new account friction.
