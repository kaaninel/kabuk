# Kabuk — Tool Distillation: In-House Tools vs. Best Open-Source Counterparts

> **Purpose:** Inventory every subsystem Kabuk currently hand-rolls, note its actual condition (verified Aug 2026), and map it to the best-maintained open-source alternative. The goal is to decide where adopting mature OSS (or newer, much better agentic models) buys capability with less maintenance than our own code.

**How to read the recommendations:**
- **Adopt** — mature OSS that clearly beats our hand-rolled code.
- **Evaluate** — worth a spike; depends on deployment model (sidecar vs in-process).
- **Keep** — our implementation is fine or the OSS alternative isn't a fit for Flutter/Dart.
- ⚠️ marks subsystems that are currently fragile or broken.

Most strong OSS here is Python/Rust/service-based, so the practical model is **self-hosted sidecars** (Docker) that the Flutter app talks to over HTTP — not in-process libraries. Kabuk already does this shape with its Usenet local stream server.

---

## 1. Web ingestion & interpretation (the Firecrawl gap)

Kabuk fetches HTTP pages and turns them into "channels" via three hand-rolled layers:
`web_extractor.dart` (HTML→markdown via embedded WebView JS + regex fallback), `reader_mode.dart` (article extraction + og:image), `semantic_extractor.dart` (LLM + JSON-LD/microdata → entities), and `WebChannelView` (the channel UI). This is exactly what Firecrawl does, and it's the least robust part of the app.

| Kabuk in-house | Current condition & shortcomings | OSS counterpart | Notes |
|---|---|---|---|
| `web_extractor.dart` — HTML→markdown (WebView JS + regex fallback) | ⚠️ Fragile. Depends on WebView rendering in-app; regex fallback is brittle; JS-heavy sites fail; no proxy/robots/rate handling. | **Firecrawl** (AGPL-3.0, 168k★, self-hostable) — scrape→clean markdown/JSON, search, crawl, map, interact, agent; **Trafilatura** (Apache-2.0) — best benchmarked OSS text extractor; **Mozilla Readability**; **Jina Reader** (`r.jina.ai`) | Firecrawl is the direct counterpart the user identified. Trafilatura is the lean, no-service alternative for text extraction. |
| `reader_mode.dart` — article extraction, reading-time, og:image | ⚠️ Duplicates Trafilatura/Readability logic; article body quality varies widely. | Trafilatura, Readability, Firecrawl `scrape` | Replace extraction core with Trafilatura via a thin sidecar, or Firecrawl for JS-heavy sites. |
| `semantic_extractor.dart` — LLM + JSON-LD/microdata → entities + relationships | ⚠️ Depends on the (unreliable) local LLM for entity extraction; schema.org mining is partial; no temporal tracking. | **Graphiti** (Apache-2.0, 30k★) — temporal knowledge graph w/ provenance, hybrid retrieval; Firecrawl `extract`/`agent` for structured JSON; **Pydantic-based extractors** | Our entity graph is exactly Graphiti's use case. See §5. |
| `WebChannelView` / `channel_page.dart` — render page as a "channel" | ⚠️ Dead code for `channel_page.dart`; WebChannelView is a bespoke semantic browser. | Firecrawl (`scrape`→markdown) + any markdown renderer | The "channel" abstraction survives; swap the ingestion underneath. |

**Recommendation:** **Adopt Firecrawl** (self-hosted) as the default web-ingestion backend with Trafilatura as a lightweight local fallback. Keep `WebChannelView` as the UI, feed it Firecrawl markdown + structured data instead of regex-extracted HTML.

---

## 2. Feed sources / social platforms

| Kabuk in-house | Current condition & shortcomings | OSS counterpart | Notes |
|---|---|---|---|
| `reddit_source.dart` — unauthenticated Reddit JSON | ⚠️ Reddit aggressively 429/403s unauthenticated requests; errors silently swallowed → stale feeds. | **PRAW** (Python, official API); **RSSHub** (routes Reddit→RSS); Reddit's own OAuth API | RSSHub converts Reddit (and YouTube, Twitter, etc.) into clean RSS — one integration covers many sources. |
| `fourchan_plugin.dart` / `fourchan_source.dart` | Works; no search/trending (UnsupportedError). | RSSHub has 4chan routes | Low priority. |
| `rss_source.dart` (RSS/Atom parser) | Works (handles RSS2 + Atom). | Trafilatura (feeds/sitemaps); `feedparser` (Python) | Keep — RSS parsing is solved and ours works. |
| `youtube_plugin.dart` (youtube_explode_dart) | Works for search/metadata; playback goes through media_kit. Breaks whenever YouTube changes APIs. | **yt-dlp** (sidecar) — most robust YouTube extraction; **RSSHub**; Invidious API | yt-dlp as a sidecar is far more resilient than an in-Dart parser. |
| `hackernews_plugin.dart` | Works (Firebase + Algolia APIs). | n/a — HN APIs are already OSS-friendly | Keep. |
| `wikipedia_plugin.dart` | Works. | n/a — Wikipedia API is open | Keep. |
| `soundcloud_plugin.dart` / `bandcamp_plugin.dart` | Works for search/resolve; no channel/trending. | RSSHub routes for both | Evaluate RSSHub instead of bespoke clients. |
| **All of the above** | 8 separate bespoke adapters, each breaking when the platform changes. | **RSSHub** (MIT, 30k★+) — universal feed gateway for 800+ sources | One maintained gateway replaces most per-source scrapers. |

**Recommendation:** **Adopt RSSHub** as a sidecar feed gateway; keep the plugin layer as a thin adapter that talks to it. **Adopt yt-dlp** sidecar for video extraction. This collapses most of the maintenance surface of §2.

---

## 3. Usenet stack

Fully hand-rolled in Dart (`lib/platform/shared/usenet/`, 13 files): Newznab indexer client, NNTP client + connection pool, NZB parser, yEnc decoder, par2 engine, RAR extractor, progressive stream pipeline + local HTTP server, provider monitor, credential store, resolver.

| Kabuk in-house | Current condition | OSS counterpart | Notes |
|---|---|---|---|
| Newznab indexer client | Works. | **Prowlarr** (indexer manager, arr stack) | Use Prowlarr to aggregate indexers instead of bespoke client. |
| NNTP client + pool | Works. | **SABnzbd** / **NZBGet** (battle-tested downloaders) | Our pipeline works but is a huge, novel surface. |
| NZB parser / yEnc decoder / par2 / RAR | Works (par2/rar are notable achievements in Dart). | **par2cmdline**/**parpar**, 7-Zip/unrar; SABnzbd does all of this | These are the rarest and most valuable parts — consider *wrapping* OSS binaries instead of re-implementing. |
| Stream pipeline + local HTTP server | Works (video now plays). | n/a (novel) | Keep — this is the product differentiator (stream-while-downloading). |
| Resolver / "Find on Usenet" | Works. | **Radarr/Sonarr** (movie/TV management + metadata) | Consider arr-stack for metadata/title matching; we already have TVmaze/TMDB/TVDb clients. |

**Recommendation:** **Keep** the streaming pipeline (differentiator). **Wrap** par2/RAR via native sidecar binaries (or a SABnzbd/NZBGet instance) rather than maintaining pure-Dart implementations. **Evaluate** Prowlarr for indexer management.

---

## 4. LLM + agent layer

This is where new agentic models change the calculus most. Kabuk hand-rolls: `LlmService`/`HttpLlmService`/`LocalLlmService` (llamadart), `TieredLlmService`, `PrivacyFilter`, an isolate `AgentRuntime`, the tool-calling loop (`_streamWithToolHandling`), and 11 domain agents.

| Kabuk in-house | Current condition & shortcomings | OSS counterpart | Notes |
|---|---|---|---|
| On-device inference (`local_llm.dart` via llamadart) | ⚠️ Works but small GGUF models are bad at tool-calling/JSON; agents degrade to raw text. | **Ollama**, **llama.cpp** (ggml), **LM Studio** | Same engine family; the model matters more than the runtime. New open models (Qwen3, DeepSeek, Llama, Gemma) are dramatically better at structured output. |
| Agent runtime + tool-calling loop (`base.dart`, `isolate_runtime.dart`) | ⚠️ Isolates fall back to in-process; tool-call JSON parsing is brittle; no code execution; no graph orchestration. | **smolagents** (Apache-2.0, 28.8k★) — code agents, model-agnostic, MCP tool support; **LangGraph**; **Microsoft Agent Framework** (ex-AutoGen); **Mastra**, **CrewAI** | Our hand-rolled loop reproduces ~20% of what these frameworks do. smolagents' "think in code" style is more reliable than dict-tool-calling for local models. |
| Router + 11 domain agents | ⚠️ All run on base tier (see IMPROVEMENT_ROADMAP E.1); keyword fallbacks mask weak models. | Same frameworks; or keep our agent layer and just swap the model + fix tiering | The agent *concepts* are fine; the orchestration can stay, but model quality + tier selection must be fixed first. |
| `PrivacyFilter` (local-LLM anonymization before remote calls) | ⚠️ Doubles latency; regex fallback is weak. | n/a (novel); consider model-agnostic PII scrubbers | Keep concept, simplify. |
| Tool calling protocol (`AgentTool` JSON schema → LLM) | Works with good models; fragile with local ones. | smolagents/LangGraph tool specs; MCP itself (adopt MCP as the tool protocol) | **MCP is the natural adoption here** — it's the open standard for exactly this, and Graphiti/Firecrawl already ship MCP servers. |

**Recommendation:** **Keep** our agent/LLM abstraction as the product layer, but **fix E.1/E.2** (tier selection + model choice) and **adopt MCP** as the tool protocol so third-party servers (Firecrawl, Graphiti) plug in directly. New open models should be the base tier — the framework matters less than the model now.

---

## 5. Knowledge store / memory

Kabuk stores everything as RDF triples in SQLite/Drift (`lib/knowledge/`) with FTS5, a QueryBuilder, change events, and a hand-rolled entity graph (`semantic_extractor` + `WebPage.memberEntities`). This is effectively a knowledge graph with no temporal model.

| Kabuk in-house | Current condition & shortcomings | OSS counterpart | Notes |
|---|---|---|---|
| RDF triple store (Drift/SQLite) | Works; schemaVersion 4. | **Oxigraph** (Rust, RDF store), **Apache Jena** | Ours is fine for a single-device app. |
| Entity/relationship graph (semantic extraction) | ⚠️ LLM-dependent, no temporal validity, no provenance, dedup is hand-written heuristics (see `web_channel_view.dart` ~200 lines of dedup). | **Graphiti** (Apache-2.0, 30k★) — temporal context graph, provenance, hybrid semantic+keyword+graph retrieval, MCP server, Neo4j/FalkorDB backends | Graphiti is the direct OSS answer to "LLM extracts entities+relations from web content." Our dedup heuristics exist because we lack a real graph DB. |
| Agent memory (`AgentMemoryMixin`) | Works (50-entry cap + prune). | **mem0**, **Letta** (MemGPT), **Zep**, **LangMem** | Evaluate Graphiti/mem0 for long-term memory instead of triple-based preference storage. |
| `ArticleData` + `WebPage` entities | ⚠️ 48h unread expiry and 200-item feed cap (TODO #6/#7). | n/a (data model, not a tool) | Fix at the store level; unrelated to OSS. |

**Recommendation:** **Evaluate Graphiti** as the semantic layer backend (sidecar with FalkorDB/Neo4j). It directly replaces the hand-written dedup and gives temporal facts + provenance + hybrid search. Keep Drift as the operational store for chat/feed state.

---

## 6. Search & retrieval

| Kabuk in-house | Current condition | OSS counterpart | Notes |
|---|---|---|---|
| FTS5 full-text search (`search()`) | Works. | **Meilisearch**, **Typesense**, **tantivy** (embedded Rust), **sqlite-vec** | Keep FTS5 for on-device; sidecar Meilisearch/Typesense only if multi-device scale is needed. |
| Semantic search | ⚠️ Planned in docs, not implemented as vector search (no embeddings pipeline). | Graphiti (hybrid retrieval), **LanceDB**, **Qdrant**, **Chroma**, **sqlite-vec** | Fold into Graphiti adoption rather than building separate embeddings. |

---

## 7. Device sync / mesh

| Kabuk in-house | Current condition | OSS counterpart | Notes |
|---|---|---|---|
| UDP multicast discovery + HTTP replication (`device_sync.dart`, `mesh_sync.dart`) | Works at a basic level. | **Syncthing** (embedded/API), **Yjs**/CRDT, **CouchDB/PouchDB**, **Automerge** | Evaluate Syncthing for file/knowledge replication; CRDTs if real-time multi-device edits matter. |
| Nostr relays (WebSocket) | Works (NIP-01/19/44/25/28). | **nostr-tools** (JS), **rust-nostr**, **NDK** | Keep — Nostr is already the OSS protocol; ours is fine. |

---

## 8. Media & metadata

| Kabuk in-house | Current condition | OSS counterpart | Notes |
|---|---|---|---|
| media_kit playback | Works (already OSS). | media_kit (keep) | Keep. |
| TVmaze/TMDB/TVDb clients | Works. | **Radarr/Sonarr** metadata; **Jellyfin** | Keep clients; arr stack only if building a library-manager. |

---

## 9. Platform plumbing (Vault/Auth/Notifications)

| Kabuk in-house | Current condition | OSS counterpart | Notes |
|---|---|---|---|
| Vault (AES-256-GCM files) | Works. | `flutter_secure_storage`, platform keychains | Keep. |
| Auth (secp256k1 keys + biometrics) | Works. | n/a (Nostr-native) | Keep. |
| Notifications / background refresh / QR exchange | Works; desktop refresh is a no-op. | Standard Flutter plugins | Keep. |

---

## Summary: Build vs. Adopt

| Area | Verdict | Effort | Primary win |
|---|---|---|---|
| Web ingestion (Firecrawl/Trafilatura) | **Adopt** | Medium | Fixes the weakest part of the app; LLM-ready markdown + structured data |
| Feed gateway (RSSHub) + yt-dlp | **Adopt** | Low | Collapses 8 bespoke scrapers into one maintained gateway |
| Agent model & tiering (E.1/E.2) | **Fix now** | Low–Med | Biggest perceived-quality win; new open models make agents actually work |
| MCP tool protocol | **Adopt** | Medium | Lets Firecrawl/Graphiti/others plug in natively; replaces hand-rolled tool protocol |
| Semantic knowledge graph (Graphiti) | **Evaluate** | High | Real graph w/ temporal facts + provenance; deletes dedup heuristics |
| Usenet stack | **Keep + wrap** | Low | Streaming pipeline stays; wrap par2/rar via binaries |
| Sync (Syncthing/CRDT) | **Evaluate later** | — | Only when multi-device matters |
| LLM/agent framework (smolagents/LangGraph) | **Defer** | — | Our layer is thin; swap the model first, revisit if orchestration grows |

**Cheapest highest-ROI path:** fix LLM tiering/model choice (E.1/E.2) → adopt Firecrawl/Trafilatura for web ingestion → adopt RSSHub + yt-dlp → adopt MCP. Graphiti and the arr stack are larger investments worth a dedicated spike.

*Compiled Aug 17, 2026 from code inspection; counterpart facts (stars/licenses) verified against project READMEs on GitHub the same day.*