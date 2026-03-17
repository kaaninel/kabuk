# Wallet, Zaps & Lightning Network — Implementation Report

**Status:** Not implemented. This document describes what currently exists, what needs to be built, and the recommended implementation plan.

---

## Current State

### What Exists

| Feature | Location | Status |
|---|---|---|
| `lud16` field on `NostrProfile` | `lib/services/nostr.dart:NostrProfile` | Stored + displayed |
| Profile metadata fetch (kind 0) | `nostr_service_impl.dart:fetchProfileCached` | Full |
| No payment flow exists | — | ❌ Not started |
| No NIP-47 NWC connection | — | ❌ Not started |
| No NIP-57 zap events | — | ❌ Not started |

### Why It's Deferred

These three features (LUD-16, NIP-57, NIP-47) form a tightly coupled **payments layer**. Implementing only one in isolation produces a broken user experience:

- **LUD-16 without NIP-47** → you can fetch an invoice but you have no wallet to pay it.
- **NIP-57 without LUD-16** → you can't resolve where to send the payment.
- **NIP-47 without NIP-57** → you have a wallet but zap events are never published to relays.

All three should be built together as a single vertical feature slice.

---

## LUD-16 — Lightning Address

### Specification
A Lightning Address looks exactly like an email address (`user@domain.com`). It's a human-readable alias for a LNURL-pay endpoint.

### Resolution Flow
```
lud16 = "alice@wallet.example"
            │
            ▼
 GET https://wallet.example/.well-known/lnurlp/alice
            │
            ▼
 Response (LNURL-pay metadata):
 {
   "callback": "https://wallet.example/lnurlp/alice/callback",
   "minSendable": 1000,      // millisats
   "maxSendable": 1000000000,
   "metadata": "[[\"text/plain\",\"Pay Alice\"]]",
   "tag": "payRequest",
   "allowsNostr": true,       // This server accepts NIP-57 zap requests
   "nostrPubkey": "<server-pubkey>"
 }
```

### What Needs to Be Built

1. **`LightningAddress.resolve(lud16) → LnurlPayMetadata`** — HTTP GET, parse response, validate `minSendable`/`maxSendable`.
2. **`LightningAddress.fetchInvoice(callback, amountMsat, zapRequest?) → String`** — HTTP GET to the `callback` URL with `amount` and optional `nostr` params, returns a BOLT-11 invoice string.
3. **Cache the metadata** with a TTL (the LNURL endpoint is stable).

---

## NIP-57 — Zaps

**Kinds: 9734 (zap request) + 9735 (zap receipt)**

Reference: https://github.com/nostr-protocol/nips/blob/master/57.md

### Event Flow

```
Client                   LNURL Server              Recipient Relay
  │                          │                           │
  │  1. GET /.well-known/    │                           │
  │     lnurlp/<name>        │                           │
  │ ─────────────────────────▶                           │
  │  ← LnurlPayMetadata      │                           │
  │                          │                           │
  │  2. Build kind 9734      │                           │
  │     (unsigned zap req)   │                           │
  │                          │                           │
  │  3. GET callback?         │                           │
  │     amount=<msat>         │                           │
  │     &nostr=<encoded-9734>│                           │
  │ ─────────────────────────▶                           │
  │  ← BOLT-11 invoice        │                           │
  │                          │                           │
  │  4. Pay invoice via wallet (NIP-47 or external)     │
  │                          │                           │
  │                          │  5. Server publishes      │
  │                          │     kind 9735 receipt ───▶│
  │                          │     (once payment confirmed)
```

### Kind 9734 — Zap Request

The zap request is an **unsigned** kind 1 event that is URL-encoded and sent to the LNURL callback:

```json
{
  "kind": 9734,
  "content": "<optional comment>",
  "tags": [
    ["relays", "wss://relay1.example", "wss://relay2.example"],
    ["amount", "21000"],         // millisats
    ["lnurl", "<lnurl-bech32>"], // the original lnurl
    ["p", "<recipient-pubkey>"], // who is being zapped
    ["e", "<event-id>"]          // optional: the event being zapped
  ],
  "pubkey": "<sender-pubkey>",
  "created_at": 1234567890
}
```

### Kind 9735 — Zap Receipt

Published by the LNURL server to relay(s) listed in the zap request, after confirming payment. Clients fetch these to display zap counts and sats totals.

```json
{
  "kind": 9735,
  "created_at": 1234567890,
  "tags": [
    ["p", "<recipient-pubkey>"],
    ["P", "<sender-pubkey>"],      // the original zap sender
    ["e", "<zapped-event-id>"],    // optional
    ["bolt11", "<BOLT-11 invoice>"],
    ["description", "<JSON-encoded kind 9734 event>"],
    ["preimage", "<payment-preimage-hex>"]  // confirms payment
  ],
  "content": "",
  "sig": "<server-sig>"  // signed by the LNURL server's nostrPubkey
}
```

### Validation Rules for Clients

When receiving a kind 9735:
1. Verify `sig` is valid and signed by the `nostrPubkey` from the LNURL server metadata.
2. Verify `bolt11` invoice matches the amount in the embedded kind 9734.
3. Verify the embedded kind 9734 (in `description` tag) was signed by the claimed sender.
4. Parse `amount` from the BOLT-11 invoice to display zap totals.

### What Needs to Be Built

In `lib/services/nostr.dart` (interface additions):
```dart
/// Fetches zap receipts (kind 9735) for an event or profile.
Stream<NostrEvent> fetchZaps(String targetId, {bool isProfile = false, int limit = 50});

/// Builds a kind 9734 zap request event (unsigned) for the LNURL callback.
Future<Map<String, dynamic>> buildZapRequest({
  required String recipientPubkey,
  required int amountMsat,
  String? eventId,
  String? comment,
  required List<String> relays,
  required String lnurl,
});
```

In a new `lib/services/lightning.dart`:
```dart
abstract interface class LightningService {
  /// Resolves a Lightning Address (LUD-16) to LNURL-pay metadata.
  Future<LnurlPayMetadata> resolveLightningAddress(String lud16);

  /// Fetches a BOLT-11 invoice from a LNURL-pay callback.
  Future<String> fetchInvoice({
    required String callbackUrl,
    required int amountMsat,
    String? comment,
    Map<String, dynamic>? zapRequest,  // kind 9734 event JSON for NIP-57
  });
}
```

---

## NIP-47 — Nostr Wallet Connect (NWC)

**Kinds: 23194 (request) + 23195 (response)**

Reference: https://github.com/nostr-protocol/nips/blob/master/47.md

### What It Does

NWC allows an app (Kabuk) to send Lightning payments using a wallet the user controls (Mutiny, Alby, Phoenix, etc.) without ever touching private keys. The connection is established once via a `nostr+walletconnect://` deep link.

### Connection URI

```
nostr+walletconnect://<wallet-service-pubkey>
  ?relay=wss://relay.example
  &secret=<client-secret-hex>
  &lud16=user@wallet.example   // optional
  &perms=pay_invoice            // optional: comma-separated method list
```

The `secret` is a fresh random 32-byte hex value used as the NIP-04 / NIP-44 shared secret. The client generates a throwaway keypair where `secret` is the private key.

### Request Flow (pay_invoice)

```
Client                                    Wallet Service
  │                                           │
  │  kind 23194 (NIP-44 encrypted)            │
  │  content = encrypt({                      │
  │    "id": "<uuid>",                        │
  │    "method": "pay_invoice",               │
  │    "params": {"invoice": "<bolt11>"}      │
  │  })                                       │
  │  tags: [["p", "<wallet-service-pubkey>"]] │
  │ ──────────────────────────────────────────▶
  │                                           │
  │                   kind 23195 (encrypted)  │
  │                   content = encrypt({     │
  │                     "id": "<same-uuid>",  │
  │                     "result": {           │
  │                       "preimage": "..."   │
  │                     }                     │
  │                   })                      │
  │ ◀──────────────────────────────────────── │
```

### Supported Methods

| Method | Params | Returns |
|---|---|---|
| `get_info` | `{}` | `{ alias, color, pubkey, network, block_height, methods[] }` |
| `get_balance` | `{}` | `{ balance }` (millisats) |
| `pay_invoice` | `{ invoice }` | `{ preimage }` |
| `pay_keysend` | `{ amount, pubkey, preimage?, tlv_records? }` | `{ preimage }` |
| `make_invoice` | `{ amount, description, expiry? }` | `{ invoice, payment_hash }` |
| `lookup_invoice` | `{ invoice? \| payment_hash? }` | `{ settled_at?, preimage? }` |
| `list_transactions` | `{ from?, until?, limit?, offset?, unpaid?, type? }` | `{ transactions[] }` |
| `sign_message` | `{ message }` | `{ message, signature }` |
| `multi_pay_invoice` | `{ invoices[] }` | `{ ... }` |

### Error Codes

| Code | Meaning |
|---|---|
| `RATE_LIMITED` | Too many requests |
| `NOT_IMPLEMENTED` | Method not supported |
| `INSUFFICIENT_BALANCE` | Not enough funds |
| `QUOTA_EXCEEDED` | Monthly budget exceeded |
| `PAYMENT_FAILED` | Invoice payment failed |
| `NOT_FOUND` | Invoice/payment not found |
| `UNAUTHORIZED` | Not authorized for this operation |
| `INTERNAL` | Wallet service internal error |
| `OTHER` | Uncategorized error |

### What Needs to Be Built

```dart
// lib/services/nwc.dart

abstract interface class NwcService {
  /// Parses and stores a nostr+walletconnect:// URI.
  Future<void> connect(String connectionUri);

  /// Returns true if a wallet connection is configured.
  bool get isConnected;

  /// Retrieves wallet info and capabilities.
  Future<NwcWalletInfo> getInfo();

  /// Returns wallet balance in millisats.
  Future<int> getBalance();

  /// Pays a BOLT-11 invoice. Returns the payment preimage.
  Future<String> payInvoice(String bolt11);

  /// Creates a new invoice for receiving payments.
  Future<String> makeInvoice({required int amountMsat, String? description});

  /// Clears the stored NWC connection.
  Future<void> disconnect();
}
```

The NWC implementation should:
1. Store the connection secret in `VaultService` (encrypted at rest).
2. Use the existing NIP-44 encryption from `lib/services/nip44.dart`.
3. Use the existing relay infrastructure from `SharedNostrService`.
4. Expose the `NwcService` via a Riverpod provider.

---

## Integration Architecture

### Recommended Layer Structure

```
lib/
  services/
    lightning.dart        # LightningService interface (LUD-16 + LNURL-pay)
    nwc.dart              # NwcService interface (NIP-47 Nostr Wallet Connect)
  platform/
    shared/
      lightning_service_impl.dart   # HTTP LNURL-pay implementation
      nwc_service_impl.dart         # NIP-47 implementation using SharedNostrService
  agents/
    domains/
      lightning_agent.dart          # Agent tools: send_zap, get_balance, pay_invoice
```

### Agent Tools (LightningAgent)

```dart
AgentTool(
  name: 'send_zap',
  description: 'Sends a NIP-57 zap (Lightning payment) to a Nostr user or event.',
  parameters: {
    'recipient_pubkey': {'type': 'string'},
    'amount_sats': {'type': 'integer'},
    'event_id': {'type': 'string', 'optional': true},
    'comment': {'type': 'string', 'optional': true},
  },
  execute: _sendZap,
)

AgentTool(
  name: 'get_wallet_balance',
  description: 'Returns the current Lightning wallet balance in sats.',
  parameters: {},
  execute: _getBalance,
)

AgentTool(
  name: 'pay_invoice',
  description: 'Pays a BOLT-11 Lightning invoice.',
  parameters: {'invoice': {'type': 'string'}},
  execute: _payInvoice,
)
```

---

## Implementation Dependencies

### External Packages Needed

| Package | Purpose |
|---|---|
| No new packages needed | LNURL-pay is plain HTTP (already have `http`) |
| No new packages needed | NIP-47 uses existing NIP-44 crypto + WebSocket relay |
| `bolt11` decoder (optional) | Parse invoice amount for NIP-57 validation |

A BOLT-11 decoder is optional — the LNURL server includes the amount in the zap request anyway. A pure-Dart BOLT-11 parser can be written inline (~50 lines) for the preimage verification step.

### No Additional Dependencies Needed

All cryptographic primitives are already present:
- **NIP-44 encryption** for NWC request/response — `lib/services/nip44.dart`
- **Schnorr signing** for zap requests — `lib/platform/shared/nostr_service_impl.dart`
- **HTTP** for LNURL endpoint resolution — `http` package already in `pubspec.yaml`
- **WebSocket relay** for NWC events — `web_socket_channel` already in `pubspec.yaml`
- **Vault** for storing NWC connection secret — `lib/services/vault.dart`

---

## Implementation Priority Order

1. **`LightningService` + `LnurlPayMetadata`** — pure HTTP, no Nostr required, can be tested in isolation.
2. **NIP-57 `buildZapRequest` + `fetchZaps`** — extends existing Nostr service; enables read-only zap count display immediately.
3. **`NwcService`** — depends on NIP-44 (done) and relay infrastructure (done); enables actual payment.
4. **`LightningAgent`** — wire the three above into agent tools and expose via chat.

Estimated effort: ~600 lines of production code, 2–3 days of focused work.

---

## Security Considerations

- **NWC secret storage**: The `secret` hex from the NWC URI must be stored exclusively in `VaultService` (encrypted at rest, never in SharedPreferences or plain files).
- **Zap receipt validation**: Before displaying a zap badge, always verify the kind 9735 signature matches the LNURL server's `nostrPubkey` — otherwise any relay could forge fake zap receipts.
- **LNURL domain pinning**: Consider warning users when the `lud16` domain changes for a known profile (anti-phishing).
- **Max spend limits**: The NWC connection should enforce a configurable per-zap and daily spend cap stored in the agent's tool parameters, checked before every `pay_invoice` call.
- **No private key exposure**: NWC is specifically designed so the wallet's private keys never leave the wallet service. Kabuk only ever touches the NWC connection `secret`, not actual Bitcoin/Lightning keys.
