# Chat & Communication Protocol

> **⚠️ STATUS (Aug 2026):** Implemented for agent chat (`lib/ui/chat/chat_service.dart`) and Nostr DMs/group channels (NIP-17/28). The gRPC-based mesh described below was superseded in practice by direct WebSocket/HTTP Nostr relays (`lib/platform/shared/nostr_service_impl.dart`). NIP-44 E2E encryption is implemented. Delivery/read receipts and full multi-device sync remain planned.

## Overview

Chat is the primary interface in Kabuk. It serves two purposes:

1. **Agent Communication** — Users talk to agents to get things done. This is the "command line" of Kabuk.
2. **Human Communication** — Users message other users. Conversations with people are managed by the `ChatAgent`.

Both use the same chat UI but with different backends. The protocol is designed to support rich content (text, media, RFW widgets, tool calls) in a unified message format.

---

## Message Format

### Core Message Structure

Every message in Kabuk — whether from an agent, a person, or the system — shares a single canonical shape. This keeps rendering, storage, and synchronization uniform across all conversation types.

```dart
@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,              // UUID v7 (time-sortable)
    required String conversationId,  // UUID of the parent conversation
    required MessageSender sender,   // Who sent it (sealed)
    required DateTime timestamp,     // UTC creation time
    required MessageContent content, // The actual content (sealed)
    MessageStatus? status,           // sent, delivered, read, failed
    String? replyToId,               // If replying to another message
    Map<String, dynamic>? metadata,  // Extensible bag for agent hints, etc.
  }) = _ChatMessage;
}
```

**Design notes:**

- `id` uses UUID v7 so messages are naturally time-ordered when sorted lexicographically. This avoids a secondary index on `timestamp` for common "latest N" queries.
- `metadata` is intentionally untyped — agents may attach hints for the UI (e.g., `{"urgency": "high"}`) without requiring a schema change.
- `replyToId` enables threaded replies. The UI draws a reply-preview above the message bubble.

### Message Sender

```dart
@freezed
sealed class MessageSender with _$MessageSender {
  /// The local user typed this message.
  const factory MessageSender.user() = UserSender;

  /// An agent produced this message.
  const factory MessageSender.agent(String agentName) = AgentSender;

  /// A remote human sent this message (human-to-human chat).
  const factory MessageSender.person(String personUri) = PersonSender;

  /// The system itself (notifications, status updates).
  const factory MessageSender.system() = SystemSender;
}
```

`PersonSender.personUri` is a knowledge-store URI (`kabuk:person/<id>`) that resolves to a `schema:Person` entity with display name, avatar, and public key.

### Message Content

Content is a sealed hierarchy. Every variant must be JSON-serializable so it can be persisted in the knowledge store and transmitted over the wire.

```dart
@freezed
sealed class MessageContent with _$MessageContent {
  // ── Text ──────────────────────────────────────────────
  /// Plain text, rendered as-is.
  const factory MessageContent.text(String text) = TextContent;

  /// Rich text in CommonMark markdown.
  const factory MessageContent.markdown(String markdown) = MarkdownContent;

  // ── Media ─────────────────────────────────────────────
  /// A media attachment stored in the Vault.
  const factory MessageContent.media({
    required String blobHash,    // Content-addressed hash (SHA-256)
    required String mimeType,    // e.g. image/jpeg, video/mp4
    String? caption,
    int? width,
    int? height,
    int? durationMs,             // For audio/video
    int? sizeBytes,
  }) = MediaContent;

  // ── Agent UI ──────────────────────────────────────────
  /// An RFW widget produced by an agent.
  const factory MessageContent.widget({
    required RfwTemplate template,
    Map<String, dynamic>? data,
  }) = WidgetContent;

  /// A tool invocation (shown as "agent is working…").
  const factory MessageContent.toolCall({
    required String toolName,
    required Map<String, dynamic> arguments,
    ToolCallStatus? status,      // pending, running, completed, failed
    ToolResult? result,
  }) = ToolCallContent;

  // ── Composite ─────────────────────────────────────────
  /// Multiple content blocks in one message.
  const factory MessageContent.compound(
    List<MessageContent> parts,
  ) = CompoundContent;

  /// Actionable buttons/chips presented to the user.
  const factory MessageContent.actions({
    String? prompt,              // Optional text above the buttons
    required List<MessageAction> actions,
  }) = ActionsContent;
}
```

### Message Actions

Action buttons let agents present discrete choices. Tapping a button sends a synthetic user message with the action identifier, which the agent handles like any other input.

```dart
@freezed
class MessageAction with _$MessageAction {
  const factory MessageAction({
    required String label,                // Display text
    required String action,               // Action identifier (e.g. "confirm_delete")
    Map<String, dynamic>? params,         // Arbitrary payload
    bool? destructive,                    // Red styling hint
    bool? primary,                        // Emphasized styling hint
  }) = _MessageAction;
}
```

### Message Status

```dart
enum MessageStatus {
  /// Queued locally, not yet sent.
  sending,

  /// Delivered to relay or agent runtime.
  sent,

  /// Confirmed received by the recipient device.
  delivered,

  /// Recipient has viewed the message.
  read,

  /// Delivery failed (network, encryption error, etc.).
  failed,
}
```

For agent conversations, status transitions are: `sending → sent → read` (agents always "read" immediately). For human conversations, the full lifecycle applies.

---

## Conversation Model

### Structure

```dart
@freezed
class Conversation with _$Conversation {
  const factory Conversation({
    required String id,                    // UUID
    required ConversationType type,
    required String title,
    String? avatarUri,                     // Vault blob hash or asset path
    required DateTime lastMessageAt,
    required DateTime createdAt,
    int? unreadCount,
    List<String>? participantUris,         // For human conversations
    String? agentName,                     // For agent conversations
    ConversationSettings? settings,
  }) = _Conversation;
}

@freezed
class ConversationSettings with _$ConversationSettings {
  const factory ConversationSettings({
    bool? muted,
    bool? pinned,
    bool? archived,
    Duration? autoDeleteAfter,             // Disappearing messages
    String? customNotificationSound,
  }) = _ConversationSettings;
}
```

### Conversation Types

```dart
enum ConversationType {
  /// Talking to an AI agent.
  agent,

  /// 1:1 with another human user.
  directMessage,

  /// Multi-participant chat.
  group,

  /// Read-only system notifications channel.
  system,
}
```

### Agent Conversations

| Property | Detail |
|----------|--------|
| Default | One "Assistant" conversation connected to the Router Agent, always present |
| Spawning | Router or user can spawn a focused session (e.g., "Note Taking" → `NoteAgent`) |
| Content | Text, markdown, tool calls, RFW widgets, action buttons |
| History | Stored as `schema:Message` triples in the knowledge store |
| Context | Conversation history fed to LLM as context window (managed, compressed) |

Agent conversations are local-only — they never leave the device.

### Direct Messages

| Property | Detail |
|----------|--------|
| Participants | Exactly 2 users |
| Transport | `MeshService` — direct P2P or relayed |
| Encryption | E2E with per-conversation key (AES-256-GCM) |
| Storage | `schema:Message` triples, encrypted at rest via `VaultService` |
| Identity | Participants identified by `kabuk:person/<id>` URIs |

### Group Chats

| Property | Detail |
|----------|--------|
| Participants | 2+ users |
| Roles | `admin` (can add/remove members, change settings), `member` |
| Key management | Group key rotated on every membership change |
| Transport | Fan-out from sender via relay, or direct multicast on LAN |
| Limits | Soft cap at 256 members (relay fan-out cost) |

### System Conversations

| Property | Detail |
|----------|--------|
| Direction | One-way (system → user) |
| Content | Reminders, agent status, security alerts, update notifications |
| Interaction | Some messages include action buttons (e.g., "Update now", "Dismiss") |
| Persistence | Auto-archived after 30 days by default |

---

## Knowledge Store Mapping

All chat data is stored as RDF triples using Schema.org vocabulary.

### Conversation Triples

```
<kabuk:conversation/{id}>  rdf:type              schema:Conversation
<kabuk:conversation/{id}>  schema:name            "Grocery List Session"
<kabuk:conversation/{id}>  kabuk:conversationType "agent"
<kabuk:conversation/{id}>  kabuk:agentName        "note"
<kabuk:conversation/{id}>  schema:dateCreated     "2026-02-25T10:00:00Z"
<kabuk:conversation/{id}>  kabuk:lastMessageAt    "2026-02-25T10:05:32Z"
<kabuk:conversation/{id}>  kabuk:unreadCount      "0"
```

### Message Triples

```
<kabuk:message/{id}>  rdf:type                schema:Message
<kabuk:message/{id}>  schema:isPartOf         <kabuk:conversation/{convId}>
<kabuk:message/{id}>  schema:sender           <kabuk:person/{userId}>  | "agent:note" | "user" | "system"
<kabuk:message/{id}>  schema:dateSent         "2026-02-25T10:05:32Z"
<kabuk:message/{id}>  schema:text             "{\"type\":\"text\",\"text\":\"Hello\"}"
<kabuk:message/{id}>  kabuk:messageStatus     "sent"
<kabuk:message/{id}>  kabuk:replyTo           <kabuk:message/{replyId}>
```

`schema:text` stores the JSON-serialized `MessageContent`. This keeps the triple store schema stable while allowing content variants to evolve.

### Queries

```dart
// Latest 50 messages in a conversation
final messages = await knowledge.query()
    .subject(type: 'schema:Message')
    .where('schema:isPartOf', equals: 'kabuk:conversation/$convId')
    .orderBy('schema:dateSent', descending: true)
    .limit(50)
    .execute();

// All conversations, most recent first
final conversations = await knowledge.query()
    .subject(type: 'schema:Conversation')
    .orderBy('kabuk:lastMessageAt', descending: true)
    .execute();

// Unread conversations
final unread = await knowledge.query()
    .subject(type: 'schema:Conversation')
    .where('kabuk:unreadCount', greaterThan: '0')
    .orderBy('kabuk:lastMessageAt', descending: true)
    .execute();
```

### Riverpod Providers

```dart
/// Stream of conversations, ordered by last message time.
@riverpod
Stream<List<Conversation>> conversations(Ref ref) {
  final store = ref.watch(knowledgeStoreProvider);
  return store
      .watch(type: 'schema:Conversation')
      .map((triples) => triples.toConversations());
}

/// Stream of messages for a specific conversation.
@riverpod
Stream<List<ChatMessage>> conversationMessages(
  Ref ref,
  String conversationId,
) {
  final store = ref.watch(knowledgeStoreProvider);
  return store
      .watch(
        type: 'schema:Message',
        where: {'schema:isPartOf': 'kabuk:conversation/$conversationId'},
      )
      .map((triples) => triples.toChatMessages());
}

/// Current conversation state (selected conversation, input draft, etc.)
@riverpod
class CurrentConversation extends _$CurrentConversation {
  @override
  String? build() => null; // No conversation selected initially

  void select(String conversationId) => state = conversationId;
  void clear() => state = null;
}
```

---

## Agent Chat Flow

### Sequence Diagram

```
User                Chat UI              Router Agent        Domain Agent         Knowledge Store
  │                    │                      │                    │                     │
  │── "remind me" ────>│                      │                    │                     │
  │                    │── persist message ───────────────────────────────────────────────>│
  │                    │                      │                    │                     │
  │                    │── UserMessage ──────>│                    │                     │
  │                    │                      │── classify ───────>│                     │
  │                    │                      │   intent           │                     │
  │                    │                      │                    │                     │
  │                    │                      │── forward msg ────>│                     │
  │                    │                      │                    │── create reminder ──>│
  │                    │                      │                    │<── reminder created ─│
  │                    │                      │                    │                     │
  │                    │                      │<── AgentResponse ──│                     │
  │                    │                      │   (text + RFW)     │                     │
  │                    │                      │                    │                     │
  │                    │── persist response ──────────────────────────────────────────────>│
  │                    │<── render response ──│                    │                     │
  │<── display ────────│                      │                    │                     │
```

### Message Lifecycle (Agent Chat)

1. **User types message** → `ChatMessage` created with `status: sending`.
2. **Persist** → Message written to knowledge store. UI updates reactively.
3. **Dispatch** → Message sent to Router Agent via agent runtime.
4. **Route** → Router classifies intent, selects domain agent, forwards with context.
5. **Execute** → Domain agent processes message, may invoke tools (each tool call emits a `ToolCallContent` message with `status: pending`).
6. **Respond** → Agent returns response (text, widget, compound). Written to knowledge store.
7. **Render** → UI picks up new message via Riverpod stream, renders appropriate bubble.

### Streaming Responses

LLM-generated text is streamed token-by-token for responsive UX.

```dart
/// Handles streaming agent responses into the knowledge store.
class StreamingResponseHandler {
  final KnowledgeStore _store;
  final String _messageId;
  final StringBuffer _buffer = StringBuffer();

  StreamingResponseHandler(this._store, this._messageId);

  /// Called for each token from the LLM.
  Future<void> onToken(String token) async {
    _buffer.write(token);
    await _store.mutate((store) {
      store.upsert(
        subject: Uri.parse('kabuk:message/$_messageId'),
        predicates: {
          'schema:text': jsonEncode({
            'type': 'markdown',
            'markdown': _buffer.toString(),
          }),
        },
      );
    });
  }

  /// Called when streaming completes.
  Future<void> onComplete() async {
    await _store.mutate((store) {
      store.upsert(
        subject: Uri.parse('kabuk:message/$_messageId'),
        predicates: {
          'kabuk:messageStatus': 'sent',
        },
      );
    });
  }
}
```

**UI behavior during streaming:**

- A placeholder message bubble appears immediately with a typing indicator.
- As tokens arrive, the bubble content grows. Markdown is re-rendered incrementally.
- Scroll position auto-follows the bottom of the conversation.
- If the user scrolls up mid-stream, auto-follow pauses. A "↓ New content" chip appears.

### Tool Call Display

When an agent invokes a tool, the UI shows the progression:

```
┌─────────────────────────────────────────┐
│  🔧 create_note                         │
│  ┌───────────────────────────────────┐  │
│  │ Status: Pending...                │  │
│  │ Arguments:                        │  │
│  │   title: "Grocery list"           │  │
│  │   body: "Milk, eggs, bread"       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
         ↓ (after execution)
┌─────────────────────────────────────────┐
│  ✅ create_note — completed              │
│  ┌───────────────────────────────────┐  │
│  │ Result: Note created successfully │  │
│  │ Note ID: kabuk:note/a1b2c3        │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

Tool call states:

| Status | Icon | Description |
|--------|------|-------------|
| `pending` | `⏳` | Tool invocation queued |
| `running` | `🔧` | Tool is currently executing |
| `completed` | `✅` | Tool finished successfully |
| `failed` | `❌` | Tool execution failed |

### Context Window Management

Agent conversations include a sliding context window of recent messages and relevant knowledge to keep LLM calls within token budgets.

```dart
/// Manages the context window for a conversation.
class ConversationContext {
  final String conversationId;
  final List<ChatMessage> recentMessages;
  final Map<String, dynamic> relevantKnowledge;
  final String? activeAgentName;

  const ConversationContext({
    required this.conversationId,
    required this.recentMessages,
    required this.relevantKnowledge,
    this.activeAgentName,
  });

  /// Compress context when it exceeds token budget.
  ///
  /// Strategy:
  /// 1. Keep the system prompt and last 4 messages verbatim.
  /// 2. Summarize older messages into a condensed narrative.
  /// 3. Keep only knowledge triples referenced in recent messages.
  Future<ConversationContext> compress(
    LlmService llm,
    int maxTokens,
  ) async {
    final tokenCount = estimateTokens();
    if (tokenCount <= maxTokens) return this;

    // Split into keep (recent) and summarize (older)
    final keep = recentMessages.take(4).toList();
    final older = recentMessages.skip(4).toList();

    final summary = await llm.summarize(
      older.map((m) => m.toPlainText()).join('\n'),
      maxTokens: maxTokens ~/ 4,
    );

    return ConversationContext(
      conversationId: conversationId,
      recentMessages: [
        ChatMessage(
          id: 'summary',
          conversationId: conversationId,
          sender: const MessageSender.system(),
          timestamp: DateTime.now(),
          content: MessageContent.text(
            '[Conversation summary: $summary]',
          ),
        ),
        ...keep,
      ],
      relevantKnowledge: _pruneKnowledge(keep),
      activeAgentName: activeAgentName,
    );
  }

  int estimateTokens() {
    // ~4 chars per token, rough estimate
    final textLength = recentMessages
        .map((m) => m.toPlainText().length)
        .fold(0, (a, b) => a + b);
    return textLength ~/ 4;
  }

  Map<String, dynamic> _pruneKnowledge(List<ChatMessage> keep) {
    // Keep only knowledge referenced by recent messages
    final mentionedUris = <String>{};
    for (final msg in keep) {
      mentionedUris.addAll(_extractUris(msg));
    }
    return Map.fromEntries(
      relevantKnowledge.entries
          .where((e) => mentionedUris.contains(e.key)),
    );
  }

  Set<String> _extractUris(ChatMessage msg) {
    // Extract kabuk: URIs mentioned in message content
    final uriPattern = RegExp(r'kabuk:\S+');
    final text = msg.toPlainText();
    return uriPattern.allMatches(text).map((m) => m.group(0)!).toSet();
  }
}
```

### Conversation Forking

Users can branch a conversation at any point:

1. Long-press a message → "Fork conversation from here"
2. Creates a new `Conversation` with messages up to that point copied
3. The original conversation is unaffected
4. Useful for exploring alternative agent interactions

---

## Human-to-Human Chat Protocol

### Identity & Discovery

Users are identified by `kabuk:person/<id>` URIs. Discovery happens via:

1. **QR Code** — Scan another user's identity QR (contains public key + relay address)
2. **Proximity** — Bluetooth LE or local network broadcast
3. **Relay lookup** — Search by username on a shared relay server
4. **Manual** — Paste a contact URI

Each user's identity is a key pair:

```dart
@freezed
class UserIdentity with _$UserIdentity {
  const factory UserIdentity({
    required String id,               // Unique user ID
    required String displayName,
    required Ed25519PublicKey signingKey,
    required X25519PublicKey exchangeKey,
    required String relayAddress,     // Default relay server
    String? avatarHash,
  }) = _UserIdentity;
}
```

### Transport Layer

Messages between users go through `MeshService`, which abstracts the transport:

```
┌────────────┐                          ┌────────────┐
│   Sender   │                          │  Receiver  │
│            │                          │            │
│  ChatAgent │──┐                    ┌──│  ChatAgent │
│            │  │                    │  │            │
└────────────┘  │                    │  └────────────┘
                ▼                    ▼
         ┌─────────────────────────────────┐
         │          MeshService            │
         │                                 │
         │  ┌──────────┐  ┌────────────┐  │
         │  │  Direct   │  │   Relay    │  │
         │  │  (P2P)    │  │  (Server)  │  │
         │  └──────────┘  └────────────┘  │
         │                                 │
         │  ┌──────────────────────────┐  │
         │  │    Offline Queue         │  │
         │  │  (Store-and-Forward)     │  │
         │  └──────────────────────────┘  │
         └─────────────────────────────────┘
```

**Transport selection strategy:**

1. **Direct (P2P)** — If both users are on the same local network (discovered via mDNS), use direct TCP/QUIC connection. Lowest latency, no server dependency.
2. **Relay** — If not directly reachable, route through the user's configured relay server. The relay sees only encrypted blobs.
3. **Offline Queue** — If the recipient is unreachable, the relay stores messages (up to a configurable TTL, default 30 days). Messages are delivered when the recipient reconnects.

### Encryption

All human-to-human messages are end-to-end encrypted. The relay server never sees plaintext.

#### Key Exchange

```
Alice                                          Bob
  │                                              │
  │── ExchangeRequest(Alice.exchangeKey) ──────>│
  │                                              │
  │<── ExchangeResponse(Bob.exchangeKey) ───────│
  │                                              │
  │  shared = X25519(Alice.private, Bob.public)  │
  │  conversationKey = HKDF(shared, salt, info)  │
  │                                              │
```

#### Message Encryption Flow

```
1. Generate ephemeral X25519 key pair (for forward secrecy)
2. Derive message key:
     messageKey = HKDF(
       X25519(ephemeral.private, recipient.exchangeKey),
       salt = conversationId,
       info = "kabuk-chat-v1"
     )
3. Encrypt:
     ciphertext = AES-256-GCM(
       key = messageKey,
       nonce = random(12 bytes),
       plaintext = serialize(MessageContent),
       aad = conversationId || senderId || timestamp
     )
4. Sign:
     signature = Ed25519.sign(
       sender.signingKey.private,
       ciphertext || ephemeral.publicKey
     )
5. Package into ChatEnvelope
```

#### Forward Secrecy

Each message uses a fresh ephemeral key pair. Compromising a long-term key does not reveal past messages. The protocol uses a simplified Double Ratchet:

- **Sending ratchet** — New ephemeral key per message (or per batch, configurable).
- **Receiving ratchet** — Derive decryption key from sender's ephemeral + own long-term key.
- **Chain key** — Optional optimization: derive a chain key from the shared secret and ratchet it with each message to avoid a full key exchange per message. Fall back to fresh ephemeral keys every N messages.

### Wire Format

Messages are serialized as Protocol Buffers for compact encoding.

```protobuf
syntax = "proto3";

package kabuk.chat.v1;

message ChatEnvelope {
  string id = 1;                      // Message UUID
  string conversation_id = 2;         // Conversation UUID
  string sender_id = 3;               // Sender's kabuk person ID
  bytes encrypted_content = 4;        // AES-256-GCM ciphertext
  bytes sender_signature = 5;         // Ed25519 signature
  int64 timestamp_ms = 6;             // Unix timestamp in milliseconds
  bytes ephemeral_public_key = 7;     // X25519 ephemeral public key
  bytes nonce = 8;                    // AES-GCM nonce (12 bytes)
  uint32 protocol_version = 9;        // Protocol version for upgrades
}

message ChatBatch {
  repeated ChatEnvelope messages = 1;
}

// ── Sync RPCs ───────────────────────────────────────

message SyncRequest {
  string conversation_id = 1;
  int64 since_timestamp_ms = 2;
  int32 limit = 3;
}

message SyncResponse {
  repeated ChatEnvelope messages = 1;
  bool has_more = 2;
  int64 server_timestamp_ms = 3;
}

// ── Delivery Acknowledgments ────────────────────────

message DeliveryAck {
  string message_id = 1;
  string conversation_id = 2;
  DeliveryStatus status = 3;
  int64 timestamp_ms = 4;
}

enum DeliveryStatus {
  DELIVERY_STATUS_UNSPECIFIED = 0;
  DELIVERED = 1;
  READ = 2;
}

message DeliveryAckBatch {
  repeated DeliveryAck acks = 1;
}

// ── Relay Service ───────────────────────────────────

service ChatRelay {
  // Send a message (or batch) to the relay for delivery
  rpc Send(ChatBatch) returns (SendResponse);

  // Pull messages since a timestamp
  rpc Sync(SyncRequest) returns (SyncResponse);

  // Stream incoming messages in real time
  rpc Subscribe(SubscribeRequest) returns (stream ChatEnvelope);

  // Acknowledge delivery/read
  rpc Acknowledge(DeliveryAckBatch) returns (AckResponse);
}

message SubscribeRequest {
  // Empty — server pushes all messages for the authenticated user
}

message SendResponse {
  bool accepted = 1;
  string error = 2;
}

message AckResponse {
  bool accepted = 1;
}
```

### Sync Protocol

Synchronization ensures message consistency across devices and after offline periods.

```
Device A                    Relay                     Device B
    │                         │                           │
    │── Subscribe() ─────────>│                           │
    │                         │<── Subscribe() ───────────│
    │                         │                           │
    │── Send(envelope) ──────>│                           │
    │                         │── stream envelope ───────>│
    │                         │                           │
    │                         │<── Ack(delivered) ────────│
    │<── stream Ack ──────────│                           │
    │                         │                           │

 (Device A goes offline)

    │                         │<── Send(envelope) ────────│
    │                         │   (queued for A)          │
    │                         │                           │

 (Device A comes back online)

    │── Sync(since=T) ──────>│                           │
    │<── SyncResponse ───────│                           │
    │   (queued messages)     │                           │
```

**Sync rules:**

1. On connection, call `Sync(since=lastSeenTimestamp)` for each conversation.
2. Process and persist received messages into the knowledge store.
3. Send any locally queued outgoing messages (`status: sending`).
4. Transition to real-time `Subscribe()` stream for ongoing delivery.
5. Periodically send `DeliveryAck` batches.

### Conflict Resolution

Messages are append-only — there are no edits or deletes at the protocol level (message deletion is a local UI action that soft-deletes the triple). Ordering conflicts (messages arriving out of order) are resolved by sorting on `timestamp_ms` with `id` as tiebreaker.

---

## Group Chat Protocol

### Group Creation

```dart
Future<Conversation> createGroup({
  required String title,
  required List<String> memberUris,
}) async {
  // 1. Generate group conversation key
  final groupKey = await AuthService.generateSymmetricKey();

  // 2. Wrap group key for each member
  final wrappedKeys = <String, Uint8List>{};
  for (final uri in memberUris) {
    final memberKey = await knowledge.getPublicKey(uri);
    wrappedKeys[uri] = await AuthService.wrapKey(
      groupKey,
      memberKey,
    );
  }

  // 3. Create conversation in knowledge store
  final conversation = await knowledge.mutate((store) {
    final id = generateId();
    store.insert(
      subject: Uri.parse('kabuk:conversation/$id'),
      predicates: {
        'rdf:type': 'schema:Conversation',
        'schema:name': title,
        'kabuk:conversationType': 'group',
        'schema:dateCreated': DateTime.now().toIso8601String(),
        'kabuk:participants': jsonEncode(memberUris),
      },
    );
    return id;
  });

  // 4. Distribute wrapped keys to members via MeshService
  await meshService.distributeGroupKey(
    conversationId: conversation,
    wrappedKeys: wrappedKeys,
  );

  return conversation;
}
```

### Key Rotation

Group keys are rotated whenever membership changes:

1. **Member added** — Generate new group key, wrap for all current members + new member, distribute.
2. **Member removed** — Generate new group key, wrap for remaining members only, distribute. The removed member's wrapped key is not included.
3. **Periodic** — Optional: rotate every N days for extra security.

### Member Roles

| Role | Permissions |
|------|-------------|
| `admin` | Add/remove members, change group title/avatar, promote/demote members, delete group |
| `member` | Send messages, leave group |

The group creator is the initial admin. Admin status can be transferred or shared.

---

## Chat UI Design

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    ChatShell                        │
│  ┌────────────┐  ┌──────────────────────────────┐  │
│  │Conversation│  │      ChatMessageList          │  │
│  │  Drawer    │  │  ┌────────────────────────┐  │  │
│  │            │  │  │   MessageBubble         │  │  │
│  │ ┌────────┐ │  │  │   ├─ TextBubble        │  │  │
│  │ │ ConvTi │ │  │  │   ├─ MarkdownBubble    │  │  │
│  │ │  le    │ │  │  │   ├─ MediaBubble       │  │  │
│  │ ├────────┤ │  │  │   ├─ RfwWidgetBubble   │  │  │
│  │ │ ConvTi │ │  │  │   ├─ ToolCallBubble    │  │  │
│  │ │  le    │ │  │  │   └─ ActionButtons     │  │  │
│  │ ├────────┤ │  │  └────────────────────────┘  │  │
│  │ │ ConvTi │ │  │                              │  │
│  │ │  le    │ │  │  ┌────────────────────────┐  │  │
│  │ └────────┘ │  │  │   MessageBubble ...    │  │  │
│  │            │  │  └────────────────────────┘  │  │
│  └────────────┘  │                              │  │
│                  ├──────────────────────────────┤  │
│                  │       ChatInputBar           │  │
│                  │  ┌──────────────────┐ ┌───┐  │  │
│                  │  │  Text input      │ │ ⬆ │  │  │
│                  │  └──────────────────┘ └───┘  │  │
│                  │  📷  📎  🎤  😀              │  │
│                  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Main Chat View

- **Conversation list** in a drawer (swipe from left or tap hamburger icon).
- **Current conversation** fills the main area.
- **Bottom input bar** with: text field, attachment button, send button.
- **Quick-action row** below (or above) the input: emoji, camera, file, voice note.
- **Messages** displayed as bubbles — user on the right, agent/other on the left.
- **Pull-up chat sheet** — the chat view is accessible as a bottom sheet from any view in the app, enabling quick agent interactions without navigating away.

### Message Rendering

```dart
/// Top-level message rendering. Delegates to type-specific bubble widgets.
class MessageBubbleFactory extends ConsumerWidget {
  final ChatMessage message;

  const MessageBubbleFactory({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.sender is UserSender;
    final alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 4,
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (message.replyToId != null)
            ReplyPreview(
              messageId: message.replyToId!,
              conversationId: message.conversationId,
            ),
          _buildContent(context, ref),
          MessageMeta(
            timestamp: message.timestamp,
            status: message.status,
            isUser: isUser,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    return switch (message.content) {
      TextContent(:final text) => TextBubble(
          text: text,
          isUser: message.sender is UserSender,
        ),
      MarkdownContent(:final markdown) => MarkdownBubble(
          markdown: markdown,
        ),
      MediaContent(
        :final blobHash,
        :final mimeType,
        :final caption,
      ) =>
        MediaBubble(
          blobHash: blobHash,
          mimeType: mimeType,
          caption: caption,
        ),
      WidgetContent(:final template, :final data) => RfwWidgetBubble(
          template: template,
          data: data,
        ),
      ToolCallContent(
        :final toolName,
        :final status,
        :final result,
      ) =>
        ToolCallBubble(
          toolName: toolName,
          status: status,
          result: result,
        ),
      CompoundContent(:final parts) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final part in parts)
              MessageBubbleFactory(
                message: message.copyWith(content: part),
              ),
          ],
        ),
      ActionsContent(:final prompt, :final actions) => ActionButtonsBubble(
          prompt: prompt,
          actions: actions,
          conversationId: message.conversationId,
        ),
    };
  }
}
```

### Conversation Drawer

The drawer shows all conversations sorted by recency:

```dart
class ConversationDrawer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final current = ref.watch(currentConversationProvider);

    return Drawer(
      child: Column(
        children: [
          // Header
          DrawerHeader(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Conversations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _startNewConversation(ref),
                ),
              ],
            ),
          ),

          // Conversation list
          Expanded(
            child: conversations.when(
              data: (convs) => ListView.builder(
                itemCount: convs.length,
                itemBuilder: (context, index) {
                  final conv = convs[index];
                  return ConversationTile(
                    conversation: conv,
                    selected: conv.id == current,
                    onTap: () {
                      ref
                          .read(currentConversationProvider.notifier)
                          .select(conv.id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
```

Each `ConversationTile` shows:

| Element | Source |
|---------|--------|
| Avatar | Agent icon (🤖) or person avatar from knowledge store |
| Title | Agent display name or person `schema:name` |
| Preview | First 50 chars of last message text content |
| Timestamp | Relative time ("2m ago", "Yesterday") |
| Unread badge | `kabuk:unreadCount` from conversation triple |

### Pull-Up Chat Sheet

The chat is accessible from any view via a persistent bottom sheet:

```dart
class ChatSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<ChatSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: 0.0,     // Hidden by default
      minChildSize: 0.0,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.0, 0.4, 0.9],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black.withValues(alpha: 0.1),
              ),
            ],
          ),
          child: ChatView(
            scrollController: scrollController,
            compact: true,
          ),
        );
      },
    );
  }
}
```

### Input Bar

The input bar adapts based on context:

| Context | Behavior |
|---------|----------|
| Agent chat | Shows text input + send. Quick actions: voice input, attach file |
| Human chat | Shows text input + send. Quick actions: camera, file, voice note, emoji |
| Tool result with actions | Replaces or augments input with action buttons |
| Voice mode | Input bar becomes a waveform visualizer with stop button |

```dart
class ChatInputBar extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatInputBar({super.key, required this.conversationId});

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final TextEditingController _textController = TextEditingController();
  bool _isComposing = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick actions row
          QuickActionsRow(
            conversationId: widget.conversationId,
          ),

          // Main input row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            child: Row(
              children: [
                // Attachment button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _showAttachmentOptions,
                ),

                // Text field
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onChanged: (text) {
                      setState(() {
                        _isComposing = text.trim().isNotEmpty;
                      });
                    },
                    onSubmitted: _isComposing ? _handleSubmit : null,
                    maxLines: 5,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'Message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(24),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send or voice button
                _isComposing
                    ? IconButton.filled(
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: () =>
                            _handleSubmit(_textController.text),
                      )
                    : IconButton(
                        icon: const Icon(Icons.mic),
                        onPressed: _startVoiceInput,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleSubmit(String text) {
    if (text.trim().isEmpty) return;
    ref.read(chatServiceProvider).sendMessage(
          conversationId: widget.conversationId,
          content: MessageContent.text(text.trim()),
        );
    _textController.clear();
    setState(() => _isComposing = false);
  }

  void _showAttachmentOptions() {
    // Show bottom sheet with: Camera, Photo Library, File, Voice Note
  }

  void _startVoiceInput() {
    // Start voice recording, transcribe, send as text
  }
}
```

---

## Chat Service

The `ChatService` coordinates message sending, agent dispatch, and persistence.

```dart
/// Central service for all chat operations.
///
/// Handles message persistence, agent routing, and human message delivery.
/// Registered as a Riverpod provider — never instantiated directly.
abstract class ChatService {
  /// Send a message in a conversation.
  ///
  /// For agent conversations: dispatches to the agent runtime.
  /// For human conversations: encrypts and sends via MeshService.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required MessageContent content,
    String? replyToId,
  });

  /// Create a new conversation.
  Future<Conversation> createConversation({
    required ConversationType type,
    required String title,
    String? agentName,
    List<String>? participantUris,
  });

  /// Mark messages as read up to a timestamp.
  Future<void> markAsRead(
    String conversationId,
    DateTime upTo,
  );

  /// Delete a conversation (soft delete — archive).
  Future<void> archiveConversation(String conversationId);

  /// Stream of typing indicators for a conversation.
  Stream<TypingIndicator> typingIndicators(String conversationId);

  /// Search messages across all conversations.
  Future<List<ChatMessage>> searchMessages(
    String query, {
    String? conversationId,
    DateTime? after,
    DateTime? before,
    int limit = 50,
  });
}

@freezed
class TypingIndicator with _$TypingIndicator {
  const factory TypingIndicator({
    required String conversationId,
    required MessageSender sender,
    required bool isTyping,
  }) = _TypingIndicator;
}
```

### Implementation Sketch

```dart
class ChatServiceImpl implements ChatService {
  final KnowledgeStore _knowledge;
  final AgentRuntime _agentRuntime;
  final MeshService _mesh;
  final AuthService _auth;

  ChatServiceImpl({
    required KnowledgeStore knowledge,
    required AgentRuntime agentRuntime,
    required MeshService mesh,
    required AuthService auth,
  })  : _knowledge = knowledge,
        _agentRuntime = agentRuntime,
        _mesh = mesh,
        _auth = auth;

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required MessageContent content,
    String? replyToId,
  }) async {
    // 1. Create message
    final message = ChatMessage(
      id: generateUuidV7(),
      conversationId: conversationId,
      sender: const MessageSender.user(),
      timestamp: DateTime.now().toUtc(),
      content: content,
      status: MessageStatus.sending,
      replyToId: replyToId,
    );

    // 2. Persist locally
    await _persistMessage(message);

    // 3. Route based on conversation type
    final conv = await _getConversation(conversationId);
    switch (conv.type) {
      case ConversationType.agent:
        await _handleAgentMessage(message, conv);
      case ConversationType.directMessage:
      case ConversationType.group:
        await _handleHumanMessage(message, conv);
      case ConversationType.system:
        throw UnsupportedError(
          'Cannot send messages to system conversations',
        );
    }

    return message;
  }

  Future<void> _handleAgentMessage(
    ChatMessage message,
    Conversation conv,
  ) async {
    // Build context
    final context = await _buildContext(conv);

    // Create placeholder for agent response
    final responseId = generateUuidV7();
    final placeholder = ChatMessage(
      id: responseId,
      conversationId: conv.id,
      sender: MessageSender.agent(conv.agentName ?? 'assistant'),
      timestamp: DateTime.now().toUtc(),
      content: const MessageContent.text(''),
      status: MessageStatus.sending,
    );
    await _persistMessage(placeholder);

    // Stream response from agent
    final handler = StreamingResponseHandler(_knowledge, responseId);
    await _agentRuntime.processMessage(
      message: message,
      context: context,
      agentName: conv.agentName,
      onToken: handler.onToken,
      onToolCall: (toolCall) => _persistToolCall(conv.id, toolCall),
      onComplete: handler.onComplete,
    );
  }

  Future<void> _handleHumanMessage(
    ChatMessage message,
    Conversation conv,
  ) async {
    // 1. Serialize content
    final plaintext = message.toJson();

    // 2. Encrypt for each participant
    for (final participantUri in conv.participantUris ?? []) {
      final envelope = await _encryptForRecipient(
        message: plaintext,
        recipientUri: participantUri,
        conversationId: conv.id,
      );

      // 3. Send via MeshService
      await _mesh.send(
        recipientUri: participantUri,
        data: envelope.writeToBuffer(),
      );
    }

    // 4. Update status
    await _updateMessageStatus(message.id, MessageStatus.sent);
  }
}
```

---

## Error Handling

Chat operations use sealed result types consistent with the project convention.

```dart
sealed class ChatResult<T> {
  const ChatResult();
}

class ChatSuccess<T> extends ChatResult<T> {
  final T data;
  const ChatSuccess(this.data);
}

class ChatFailure<T> extends ChatResult<T> {
  final ChatError error;
  const ChatFailure(this.error);
}

enum ChatError {
  /// Message could not be encrypted (missing recipient key).
  encryptionFailed,

  /// Network unreachable and offline queue is full.
  queueFull,

  /// Conversation not found in knowledge store.
  conversationNotFound,

  /// Agent returned an error.
  agentError,

  /// Message content validation failed.
  invalidContent,

  /// Recipient blocked the sender.
  blocked,

  /// Rate limited by relay server.
  rateLimited,
}
```

---

## Implementation Task List

### Phase 1 — Agent Chat (MVP)

Core agent-to-user communication. This is the minimum viable chat experience.

- [ ] Define `ChatMessage`, `MessageContent`, `MessageSender` Freezed classes in `lib/ui/chat/models/`
- [ ] Define `Conversation`, `ConversationSettings` Freezed classes
- [ ] Define `MessageAction`, `TypingIndicator` Freezed classes
- [ ] Implement `ChatService` abstract interface in `lib/services/chat.dart`
- [ ] Implement `ChatServiceImpl` with agent message handling
- [ ] Implement conversation CRUD in knowledge store (create, list, archive)
- [ ] Implement message persistence in knowledge store (insert, query, watch)
- [ ] Set up Riverpod providers: `conversationsProvider`, `conversationMessagesProvider`, `currentConversationProvider`, `chatServiceProvider`
- [ ] Build `ChatView` — main chat screen with message list and input bar
- [ ] Build `MessageBubbleFactory` — delegates to type-specific bubbles
- [ ] Build `TextBubble` and `MarkdownBubble` widgets
- [ ] Build `ChatInputBar` with text input and send button
- [ ] Integrate Router Agent — send user message → receive agent response
- [ ] Implement `StreamingResponseHandler` for incremental LLM output
- [ ] Build `ToolCallBubble` with pending/running/completed/failed states
- [ ] Build `RfwWidgetBubble` for agent-generated UI in chat
- [ ] Build `ActionButtonsBubble` for agent-presented choices
- [ ] Implement `ConversationContext` with token budget compression
- [ ] Build conversation list in drawer (`ConversationDrawer`, `ConversationTile`)
- [ ] Default "Assistant" conversation auto-created on first launch
- [ ] Write unit tests for `ChatServiceImpl` with mocked knowledge store and agent runtime
- [ ] Write widget tests for message bubble rendering

### Phase 2 — Rich Chat Experience

Enhanced interaction patterns and UI polish.

- [ ] Build `MediaBubble` — render images, video thumbnails, audio players
- [ ] Implement media message sending (pick photo/video/file, upload to Vault, send `MediaContent`)
- [ ] Implement `CompoundContent` rendering (multiple blocks per message)
- [ ] Implement reply-to: long-press message → reply, show `ReplyPreview` above bubble
- [ ] Implement message search across conversations (full-text on `schema:text`)
- [ ] Build pull-up `ChatSheet` (draggable bottom sheet, accessible from any view)
- [ ] Build `QuickActionsRow` — emoji, camera, file picker, voice note
- [ ] Implement voice note recording and sending as `MediaContent`
- [ ] Implement voice-to-text input (record → transcribe → send as text)
- [ ] Conversation forking (long-press message → "Fork from here")
- [ ] Agent conversation spawning (user says "let me talk to NoteAgent" → new conversation)
- [ ] Unread count tracking and badge display
- [ ] Typing indicators for agent conversations (show while LLM is generating)
- [ ] Message timestamps — group by day, show relative time
- [ ] Scroll-to-bottom button when viewing older messages
- [ ] Write unit tests for media handling and conversation forking
- [ ] Write widget tests for `ChatSheet`, `QuickActionsRow`, `MediaBubble`

### Phase 3 — Human-to-Human Chat

Encrypted messaging between users.

- [ ] Define `UserIdentity` Freezed class with signing and exchange keys
- [ ] Define `ChatEnvelope` protobuf message in `proto/chat.proto`
- [ ] Implement `ChatAgent` in `lib/agents/domains/chat_agent.dart` — manages human conversations
- [ ] Implement key exchange protocol (X25519 ECDH → HKDF → conversation key)
- [ ] Implement message encryption (AES-256-GCM with AAD)
- [ ] Implement message signing (Ed25519)
- [ ] Implement forward secrecy with ephemeral key rotation
- [ ] Implement `ChatRelay` gRPC client for relay server communication
- [ ] Integrate relay transport in `MeshService` — send encrypted envelopes
- [ ] Implement direct P2P transport in `MeshService` — mDNS discovery + QUIC
- [ ] Implement offline message queue (store in knowledge store, flush on reconnect)
- [ ] Implement `SyncProtocol` — on connect, exchange timestamps, pull missing messages
- [ ] Implement delivery status tracking (sent → delivered → read)
- [ ] Implement read receipts (send `DeliveryAck` with `READ` status)
- [ ] Implement contact discovery (QR scan, proximity, relay lookup)
- [ ] Build contact list UI integrated with knowledge store `schema:Person` entities
- [ ] Write unit tests for encryption/decryption round-trip
- [ ] Write unit tests for sync protocol with simulated message loss
- [ ] Write integration tests for full send → relay → receive flow with mock MeshService

### Phase 4 — Group Chat

Multi-participant conversations.

- [ ] Implement group creation flow (`createGroup` in `ChatService`)
- [ ] Implement group key generation and per-member wrapping
- [ ] Implement key rotation on member add/remove
- [ ] Implement group membership management (add, remove, leave)
- [ ] Implement role management (admin, member)
- [ ] Implement group message fan-out (encrypt once with group key, distribute to all)
- [ ] Build group settings UI (name, avatar, members, roles)
- [ ] Build group creation UI (select contacts, set name)
- [ ] Build member management UI (add/remove, promote/demote)
- [ ] Implement group sync protocol (handle concurrent membership changes)
- [ ] Write unit tests for group key rotation scenarios
- [ ] Write integration tests for group message delivery

---

## Open Questions

| # | Question | Impact | Proposed Resolution |
|---|----------|--------|---------------------|
| 1 | Should we implement the Double Ratchet fully or use a simplified version? | Security vs. complexity | Start with per-message ephemeral keys (simpler). Upgrade to full Double Ratchet in a later phase if needed. |
| 2 | What is the maximum offline queue TTL? | Storage on relay | Default 30 days. Configurable per-user. Relay operators set hard cap. |
| 3 | Should agents be able to initiate conversations? | UX, notification design | Yes — agents can create system messages for reminders and alerts. Requires notification integration. |
| 4 | How do we handle message content migration when `MessageContent` variants change? | Persistence stability | `schema:text` stores versioned JSON. Include a `"v"` field. Reader skips unknown variants gracefully. |
| 5 | Should media in human chats be relayed or only sent P2P? | Relay bandwidth cost | Media transferred P2P when possible. Relay stores only a thumbnail + metadata pointer. Full media fetched from sender's device on demand. |
| 6 | Group size limit? | Performance, key distribution cost | Soft limit at 256. Key distribution cost is $O(n)$ per rotation. Larger groups need a different key management scheme (e.g., tree-based). |
