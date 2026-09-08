# Kabuk — Complete Feature Map

**Purpose:** Decision document for pruning. Every feature is listed with LOC, maturity, dependencies, and whether it can be removed as a coherent unit.
**Audited:** Sep 2026. Sources: full import-graph scan, TODO.md, docs/IMPROVEMENT_ROADMAP.md, git history.

---

## 0. Headline numbers

| Metric | Value |
|---|---|
| `lib/` | 252 files · **145,114 LOC** |
| `test/` | 48 files · 13,250 LOC (~740 cases, ~9% ratio) |
| UI layer share | **69,362 LOC (48%) — zero widget tests** |
| Verified dead code | **~8,000 LOC** (UI ~7,000 + services ~900) |
| Largest single feature | **Usenet stack ~22,000 LOC (15% of app)** — mid-rework |
| Uncommitted work | 43 entries (feed/channel rework + MCP channel layer, 717/717 tests passing per FEED_CHANNEL_PLAN.md) |
| Prior restart attempt | `rework` branch — abandoned, tip commit "Deadend." |

**Core diagnosis:** the backend (agents/knowledge/services, ~47K LOC) is well-tested and matches its docs. The instability lives in (a) the UI layer — 69K LOC, untested, "Swiss-army knife" density per UX audit, and (b) two giant half-finished subsystems: Usenet (~22K) and the local-LLM tool-calling loop. The app is not "one broken thing"; it is ~10 products stapled together, most individually functional.

---

## 1. The four pillars (core identity — everything else hangs off these)

| Pillar | What it is | LOC | Status |
|---|---|---|---|
| **Chat-first UI** | 4-tab shell; chat is universal input to agents | ~4,000 core | working |
| **RDF Knowledge Store** | Single source of truth: triples (Schema.org vocab) on Drift/SQLite, FTS5, change events | ~2,700 core + 8,075 types | working, well-tested |
| **Agent system** | Router + 12 domain agents, tool-call loop over LLM | 13,625 | well-tested; local tool-calling unreliable (TODO #2) |
| **Nostr identity & social** | secp256k1 identities, NIP-01/17/19/25/28/44, DMs, channels, reactions, relays | ~6,500 (service) + UI | working |

---

## 2. Feature inventory

### A. Shell & Navigation (`lib/ui/shell.dart`, `app.dart`, `theme.dart`)
| Feature | LOC | Status |
|---|---|---|
| 4-tab shell (Explore/Chat/Vault/Apps), PageView | 1,283 | working |
| 3 nav-bar styles (classic/compact/pill) + chat sheet overlay | (in shell) | working — 3 styles is feature creep |
| Onboarding gate, theme mode, model-readiness banners, notification deep links | (in app/shell) | working |
| Theme/design tokens | 559 | working |

### B. Explore — feed aggregator (`lib/ui/explore/`, 32 files, 31,486 LOC)
| Feature | Files | LOC | Status |
|---|---|---|---|
| Feed home: sort, filter chips, content filters, pull-to-refresh, 30-min bg refresh, pagination | explore_view, explore_tab, filter_bar, empty_feed_state | 3,029 | working (fixed Aug 2026, uncommitted) |
| **OmniBar** — unified search/browse hub (local, Nostr, Usenet, TMDB, plugins, DDG, saved searches, feed mgmt) | omnibar, discovery_providers | 3,206 | working — central hub, biggest coupled file |
| Article card + detail + **unified comments** (Nostr + Reddit + 4chan) | article_card, article_detail_page, reddit/fourchan_comments | 5,892 | working — article_detail is 4,083 LOC, the largest file |
| Reader view (AI-extracted content blocks) | reader_view | 977 | working |
| **Channel trio (overlapping!)** | channel_view 754, web_channel_view 1,602, channel_page 857 | 3,213 | channel_page "intended to replace the other two"; partial adoption |
| Nostr social layer (likes/comments/reposts, profiles, threads, hashtags, semantic entity cards) | 6 files | 2,645 | working |
| **Multi-tab browsing** (Safari-style tabs + classic WebView) | explore_tab, tab_sidebar, classic_web_view, browse_session | ~1,630 | working, lightly used |
| Feed management (dup UI: sheet + page) | 2 files | 1,294 | working but duplicated |
| Quick peek WebView preview | 974 | 240 live / ~735 dead | |
| Agent channel surface | 346 | working, niche |

### C. Chat (`lib/ui/chat/`, 13 files, 9,063 LOC)
| Feature | LOC | Status |
|---|---|---|
| Conversation list (pinned AI tile, contacts row, DMs, channels, QR) | 1,478 | working |
| AI agent conversation (streaming, optimistic send) | conversation_detail + chat_service + input + bubbles | 2,044 | working |
| **Nostr DMs (NIP-17 gift-wrap)**: media, reactions, pins, typing, reply | 2,178 | working |
| Nostr channels (NIP-28) | 835 | working |
| Contact management + profiles + QR exchange | 2,205 | working |
| Inline RFW widgets in message bubbles | (message_bubble) | working |

### D. Vault (`lib/ui/vault/`, 8 files, 5,083 LOC)
| Feature | Status |
|---|---|
| Documents (block-based editor, autosave), Media gallery (camera/audio capture), Collections tree | **fully working, self-contained** — cleanest prunable unit (drop = -5,083 UI + note/collection/media/content_block types) |

### E. Apps tab (`apps_view.dart`, 1,959 LOC)
Launcher grid: bookmarks, saved RFW views, mini-apps (Notes/Calendar/Contacts/Search — CRUD demos duplicating Vault/Chat), dev section, marketplace banner. Working but duplicative.

### F. Settings (`lib/ui/settings/`, 13 files, 10,915 LOC)
| Page | LOC | Status |
|---|---|---|
| Hub | 896 | working |
| Identity mgmt (multi-identity, nsec, biometrics) | 1,142 | working |
| My profile (npub QR) | 653 | working |
| Relays | 757 | working |
| Local GGUF models (download/select/GPU) | 873 | working |
| Remote LLM endpoint | 568 | working |
| Service providers | 730 | working |
| **Usenet settings** (indexers, NNTP, cache) | 1,932 | working — huge, Usenet-bound |
| Streaming prefs | 344 | Usenet-bound |
| Feed sources page | 634 | working (dup of sheet) |
| Trace export (finetuning JSONL) | 510 | working, niche |
| Dev mode (triple inspector, cost log) | 1,073 | working |
| Device pairing | 803 | **DEAD — no entry point** |

### G. Agent system (`lib/agents/`, 31 files, 13,625 LOC)

Framework: base tool-loop (710), runtime (93), **isolate_runtime (1,379 — fallback path is the real one; TODO #3)**, llm types (365), local_llm (474), http_llm (711 — well built), tiered_llm (261 — **tier system decorative, everything runs base tier, TODO #1**), privacy_filter (483 — doubles latency, TODO #5), memory (215 — **half-dead: no agent ever saves memory**), context (193), prompts (126), messages (272), channels (117), observation (160 — write-only via concierge), concierge (104), subagent (87), cost_tracker (214), primitives (389 — mostly uncalled).

| Domain agent | LOC | Tools | Status |
|---|---|---|---|
| Router | 505 | 2 | working (3-stage dispatch) |
| System | 318 | 6 | working |
| Note | 477 | 6 | working |
| Contact | 468 | 6 | working |
| Calendar | 537 | 7 | working, but `set_reminder` never fires (no notification wiring) |
| File | 513 | 5 | working |
| Search | 417 | 4 | working |
| Identity | 679 | 12 | working |
| Messaging | 643 | 9 | working, but **unreachable via router fast path** (LLM-only routing) |
| Feed | 1,219 | 14 | working; **6 tools are Usenet config CRUD duplicating Settings** |
| Discovery | 1,108 | 13 | working; 3 tools are Usenet search/stream |
| Web | 364 | 8 | working; invoked by omnibar directly, bypassing router |

**Agent reachability from UI:** Chat → router → all (messaging only via LLM routing); omnibar → web agent directly; everything else (isolate path, rawWidget results, memory save, concierge proactive layer) unreachable/dead.

### H. LLM stack (`agents/local_llm|http_llm|tiered_llm` + `services/model_manager` + settings)
- **Local:** llamadart GGUF (MiniCPM5 1B Q4_K_M ~1.19 GB), auto-download in onboarding, GPU crash recovery. Tool-calling unreliable (regex fallback only).
- **Remote:** OpenAI-compatible + Anthropic + Ollama wire formats in one class, streaming, retries. Well built.
- **Tier system:** standard tier = alias of base. Remote-only config = 2 API calls per message. Nothing configured = misleading stub.
- **Model manager:** scans/downloads GGUF, device-RAM model picker. Working.

### I. Knowledge store (`lib/knowledge/`, 2,728 core + 8,075 types)
- Core (store/triple/query/mutation/changes/database/drift_store): working, self-contained, the data spine. Keep.
- 21 type files. Dead-ish: `event.dart` (210, write-only), `follow.dart` (140, 1 consumer). Write-only: place/product/organization (~1,360, extraction → semantic cards only).

### J. Services / Virtual OS (`lib/services/`, 12,601 + `lib/platform/`, 23,254 LOC)
| Cluster | Files | LOC | Status |
|---|---|---|---|
| Nostr (nostr, nostr_utils, nip19, nip44) | 4 | 2,908 | working |
| Extraction pipeline (web_extractor, reader_mode, semantic_extractor) | 3 | 5,478 | working, tightly coupled — adopt-per-TOOL_DISTILLATION or keep |
| Feed stack (feed, feed_refresh, content_source, channels + 2 servers, background_refresh) | 7 | 1,447 | working (uncommitted rework) |
| Media cluster (media, media_metadata, cache, model_manager, mesh, vault, auth, notification, presentation, device_sync, peer_exchange, trace_exporter) | 13 | ~1,800 | working; presentation stub; peer_exchange/trace_exporter 1-consumer |
| Platform shared impls | 24 | ~6,900 | working; dead: notification_service_impl, desktop bg refresh |
| **Usenet stack** | 16 | ~9,900 | working code, mid-rework UX; dead: credential_store, provider_monitor |

### K. Usenet stack (~22,000 LOC total — the single biggest prune unit)
Platform: usenet_service_impl, stream_pipeline, rar_extractor (pure-Dart RAR), par2_engine (Reed-Solomon), nntp_pool/client, newznab_client, nzb_parser, stream_cache, stream_server, yenc, post_processor, release_parser, resolver/orchestrator. UI: media_detail (TMDB), entity_player, usenet_detail, usenet_player, usenet settings (2,269 LOC) + dead card/sheet (~2,670). Types: usenet, tv_movie (1,254). Agent tools: 9 across feed/discovery. **The only subsystem TOOL_DISTILLATION recommends keeping in-house — it is genuinely novel (pure-Dart streaming NZB pipeline) but is one niche product inside a super-app.**

### L. Plugins (`lib/plugins/`, 4,925 LOC)
Core (plugin/content_item/context/registry/channel) 1,204 LOC + 8 bundled: Media (739), YouTube (693, Invidious/Piped — fragile), Reddit (532, API-hostile), Bandcamp (424, scraping-fragile), 4chan (368), SoundCloud (351, fragile), Wikipedia (319), HackerNews (295). No plugin tests. Dead: content_expiry (168).

### M. RFW dynamic UI (`lib/rfw/`, 1,401 LOC)
Agent-generated widgets + saved views. **Only 2 consumers** (message_bubble, apps_view). Working but narrow. Cut if saved-views/agent-widgets are cut.

### N. Misc
Marketplace (773, bundled-only), Onboarding (1,755, working), Viewers (1,691, narrow adoption).

---

## 3. Verified dead code (delete first — zero behavioral risk)

| Item | LOC |
|---|---|
| `lib/ui/shared/kabuk_keyboard.dart` (custom keyboard, never instantiated) | 2,222 |
| Usenet settings *sheet* widget (superseded by page; only 55-line provider block used) | ~1,900 |
| `SubredditPeekSheet` in quick_peek_sheet.dart | ~735 |
| `lib/ui/settings/device_pairing_page.dart` (orphaned DeviceSync UI) | 803 |
| `lib/ui/explore/usenet_card.dart` | 735 |
| `lib/ui/explore/search_dialog.dart` | 456 |
| `usenet/credential_store.dart`, `usenet/provider_monitor.dart` | 508 |
| `plugins/content_expiry.dart` | 168 |
| `platform/shared/notification_service_impl.dart` + `desktop/background_refresh_impl.dart` | 199 |
| `kabuk_snackbar.dart`, `rfw/exports.dart` | 86 |
| Agent dead surface: `handleWidgetEvent`, `RawWidgetToolResult`, `primitives.buildPrimitivePrompt/contentItemFromMap`, memory write-path | ~300 |
| **Total** | **~9,100** |

---

## 4. Prunable units (coherence-ranked — each removes cleanly with one seam)

| # | Unit | Est. LOC removed | Seam (what must be touched) |
|---|---|---|---|
| 1 | **Usenet + TMDB/media stack** (platform/usenet + UI + settings + usenet/tv_movie types + 9 agent tools) | ~22,000 | providers.dart, main.dart, omnibar/media detail, FeedService source list, media_kit deps |
| 2 | **Vault tab** | ~5,100 UI + types | shell tab, providers, capture services |
| 3 | **Extraction pipeline** (web_extractor/reader_mode/semantic_extractor) | ~5,500 | article_detail, omnibar, web_channel_view, feed_agent |
| 4 | **Channel trio** (channel_view + web_channel_view + channel_page, keep one) | 1,600–2,400 | openUrlSmart routing |
| 5 | **Explore multi-tab system** | ~1,630 | explore_view |
| 6 | **Plugins: bandcamp + soundcloud + youtube** (fragile backends) | ~1,770 | registry |
| 7 | **RFW layer** (if saved-views/agent-widgets cut) | ~1,400 + apps_view integration | providers, apps_view, message_bubble |
| 8 | **Apps tab mini-apps** (Calendar/Contacts/Search dupes) | ~800 | apps_view |
| 9 | **Isolate runtime** (collapse to plain registry) | ~1,379 | agentRuntimeProvider |
| 10 | **Trace export + dev mode + device pairing** | ~2,390 | settings |

---

## 5. What a "more basic" v2 would plausibly be

The tested, healthy ~47K-LOC backend already implements the vision. The instability comes from UI surface (69K, untested) + Usenet + local-LLM brittleness. A minimal restart keeps:

1. **Knowledge store** (core, ~2,700) — keep as-is, it's the spine and it's tested.
2. **Nostr service + identity** (~4,500) — keep, working.
3. **Agent framework** minus isolate runtime, memory mixin, tier system, privacy filter (~8,000 → ~5,000) — keep base tool-loop + 4–5 domain agents (system, note, search, web, feed).
4. **HTTP LLM** as primary; local GGUF optional-later — remove the "AI model being prepared" path entirely.
5. **Feed stack** (feed, refresh, content_source, 2–3 sources: RSS, Nostr, Reddit) + **Explore feed UI core** + **omnibar** (slimmed).
6. **Chat UI** (conversation list + detail, Nostr DMs) — keep.
7. **Settings** trimmed to identity/relays/LLM/feeds (~4,500 of 10,915).
8. **Plugins**: 2–3 working ones (HN, Wikipedia, 4chan) via the existing channel interface.

That's ~25–30K LOC vs 145K — an ~80% reduction — while keeping every *working* pillar. Everything in §4's table is what gets cut.

**Pre-restart hygiene (do first):**
- Commit or discard the 43 uncommitted changes (feed/channel rework, 717/717 passing) — it's the newest working code.
- Delete the `rework` branch (abandoned prior restart; TODO #16).
- Delete the ~9,100 LOC of verified dead code in §3 even if not restarting.
