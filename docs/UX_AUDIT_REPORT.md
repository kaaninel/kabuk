# Kabuk OS — UX/UI Audit Report

**Date**: February 28, 2026  
**Method**: Live simulator inspection (iPhone 17 Pro) + full source code review (30 UI files, ~16,840 lines)  
**Benchmarks**: Reddit, Twitter/X, Telegram, Signal, Instagram, ChatGPT, Apple Notes, iOS Settings

---

## Executive Summary

Kabuk is an ambitious agent-centric OS shell that tries to do too many things in its current state. The app combines a social feed reader, AI chatbot, camera suite, note-taking app, calendar, contacts manager, file browser, bookmark manager, and developer console — all within 4 tabs. The result is a **"Swiss Army knife" UX problem**: no single feature feels polished enough to compete with dedicated apps, and users encounter many dead-end or stub screens.

**Critical issues**: 5 screens are mostly empty placeholders, navigation is inconsistent (thread view has no back button), the Vault tab is camera-first (broken on simulator, confusing for a private-inbox use case), and the Apps tab mixes user-facing tools with developer internals.

### Severity Ratings

| Severity | Count | Description |
|----------|-------|-------------|
| **P0 — Broken** | 3 | Features that don't work or trap users |
| **P1 — Major** | 8 | Severely diminished UX, users will abandon the feature |
| **P2 — Moderate** | 9 | Friction points that reduce perceived quality |
| **P3 — Minor** | 7 | Polish items that show in competitive comparison |

---

## Tab-by-Tab Analysis

### 1. Explore Tab (Content Feed)

**What it does**: Aggregates Reddit, RSS, and Nostr posts into a unified feed with filter chips, social interactions, search, and trending topics.

**Comparable apps**: Reddit, Twitter/X, Flipboard, Apple News

#### What works well
- Card-based feed layout is familiar and readable
- Filter chips (All, Nostr, #bitcoin, r/turkey, r/all) give fast feed switching
- Nostr social layer on web content (reactions/comments on any URL) is a genuinely novel feature
- Empty fed state suggests actionable next steps ("Subscribe to r/all")

#### Issues found

| # | Issue | Severity | Benchmark |
|---|-------|----------|-----------|
| 1.1 | **Thread view has no back button or close gesture** — user opens an article detail sheet, scrolls down, and has no visible way to dismiss it except pulling the sheet down. No drag handle visible either. | P0 | Reddit: clear X button + drag handle on every sheet |
| 1.2 | **Thread view has no navigation chrome** — no app bar, no title, no status. It's a floating card with no context about where you are. | P1 | Twitter: thread view has full app bar with back arrow + "Post" title |
| 1.3 | **Article detail shows Nostr comment section with "No comments yet"** for every Reddit post. This is confusing — users expect Reddit comments, not an empty Nostr overlay. | P1 | Reddit: shows native comments. Bridging to Nostr should be opt-in or clearly explained. |
| 1.4 | **"Open in browser" as primary action** in thread view is a dead-end. The user left the app. Consider in-app WebView (Quick Peek already exists for this). | P2 | Reddit: full article rendering in-app. Flipboard: article reader mode. |
| 1.5 | **5 icon buttons in Explore app bar** (Quick Peek, Trending, Search, Settings, avatar) — too dense. Cognitive overload. | P2 | Reddit: 2 actions (inbox, avatar). Twitter: 1 action (settings via avatar). |
| 1.6 | **Quick Peek** is a URL input dialog — not "quick." Requires typing a URL. Users expect a preview on content they can already see, not a blank URL input. | P2 | Safari: 3D-touch link peek. Reddit: long-press link preview. |
| 1.7 | **Trending Topics** shows empty "Most popular hashtags" with no actual content loaded during my test. | P1 | Twitter: trending section always has content, with categories and post counts. |
| 1.8 | **Search is a modal overlay** with a single text field and no results categories, history, or suggestions. | P2 | Reddit: search has categories (Posts, Communities, People), trending searches. Instagram: Explore grid with top-level search. |
| 1.9 | **No pull-to-refresh visual indicator** — the code has RefreshIndicator but it's not visually apparent. | P3 | Reddit/Twitter: clear pull-to-refresh with spinner/animation. |
| 1.10 | **Article card action bar** has a button with no label (the share/bookmark button) — it has `AXLabel: null`. | P2 | All social apps: every action button has an icon AND a count or label. |

#### Recommendations
1. Replace the article detail bottom sheet with a full-screen page with proper AppBar (back button, title, actions)
2. Show Reddit comments natively; move Nostr comments to a secondary tab on the detail view
3. Merge Quick Peek into long-press on articles (contextual, not a standalone dialog)
4. Reduce app bar to 2-3 actions max: Search, Avatar (opens settings/profile), overflow menu
5. Make Trending Topics a section within the feed or search results, not a standalone sheet

---

### 2. Chat Tab (AI & Messaging)

**What it does**: Conversation list with pinned Kabuk AI, Nostr DMs, and topic subscriptions.

**Comparable apps**: ChatGPT, Telegram, Signal, WhatsApp

#### What works well
- Kabuk AI pinned at top is effective — it's always the first thing you see
- AI conversation detail with streaming markdown responses works well
- NIP-17 encrypted DM with protocol info banner builds trust
- Suggestion chips in empty chat state help onboarding

#### Issues found

| # | Issue | Severity | Benchmark |
|---|-------|----------|-----------|
| 2.1 | **Identity switcher shows "?" with tiny text** at top-left. Looks like a broken avatar, not an identity feature. The "?" renders as a small circle with question mark — no context about what it does. | P1 | Telegram: clear profile photo in hamburger menu. WhatsApp: Settings tab with profile. |
| 2.2 | **"New Channel" and "New Nostr DM" buttons** in app bar are Nostr-specific jargon. Non-technical users won't understand. | P2 | Telegram: "New Message" button opens a unified contact picker. Signal: single "compose" FAB. |
| 2.3 | **Nostr topic subscription appears as a "conversation"** ("Subscribed to Nostr topic #bitcoin") — but you can't chat with it. It's a feed subscription masquerading as a chat item. This is confusing. | P1 | No popular app mixes feed subscriptions with chat conversations. These belong in Explore or a separate section. |
| 2.4 | **No conversation search** — can't search within or across conversations. | P2 | Telegram/WhatsApp: search bar at top of conversation list + search within conversation. |
| 2.5 | **AI chat has no retry/regenerate button** on responses. | P2 | ChatGPT: regenerate button on every response. Claude: retry option. |
| 2.6 | **AI chat shows agent name "router"** in the response bubble. This is internal implementation detail leaking to UI. | P1 | ChatGPT: messages are from "ChatGPT", not "gpt-4-turbo" or "router". |
| 2.7 | **Chat input has markdown toolbar toggle** — most users won't understand markdown. No rich text formatting visible. | P3 | Telegram: rich text via long-press selection menu. WhatsApp: *bold*, _italic_ via formatting characters. |
| 2.8 | **AI response shows raw URIs** like `kabuk:FeedSubscription/42a76083-5bc2-4314-a1db-1900f326010d`. This is technical noise. | P1 | ChatGPT: responses are human-readable only. Technical IDs never shown. |
| 2.9 | **No conversation title or rename** — AI conversations are just "Kabuk AI" with no way to differentiate between topics. | P2 | ChatGPT: auto-generates titles, allows rename. |

#### Recommendations
1. Replace "?" identity avatar with proper profile image or generated avatar (like the one used in Explore's header)
2. Consolidate "New Channel" + "New Nostr DM" + "Add Contact" into single "+" FAB with bottom sheet picker
3. Move feed subscriptions out of Chat — they belong in Explore's filter bar or a Subscriptions section
4. Hide internal agent names and URIs from user-facing messages; format tool results as user-friendly cards
5. Add conversation titles with auto-generation from first message

---

### 3. Vault Tab (formerly Create — Private Data Storage)

> **Note:** This tab is being renamed from **Create** to **Vault**. Its purpose is shifting from camera-first content creation to a **private data inbox**: the user's personal capture and storage space, organized by the local LLM. Camera, audio recorder, and notes remain as capture modalities, but the primary framing is "capture anything and let AI organize it" rather than "create content to publish."

**What it does**: Quick-capture interface (photo, audio, notes) feeding directly into the user's private, AI-organized vault. The local LLM auto-tags and categorizes captured content.

**Comparable apps**: Apple Notes (notes), Voice Memos (audio), Google Keep (quick capture), Obsidian (organized notes)

#### What works well
- Mode bar with animated indicator is clean and intuitive
- Full-screen camera approach is immersive
- Audio capture with real-time waveform visualization is visually appealing
- Note composer has a clean, focused writing experience

#### Issues found

| # | Issue | Severity | Benchmark |
|---|-------|----------|-----------|
| 3.1 | **Camera shows "No cameras found" error on simulator** with a "Retry" button that will never work. No graceful fallback. The entire Vault tab is a dead-end on simulator/desktop. | P0 | Instagram: shows photo library picker when camera unavailable. Snapchat: shows error with alternative actions. |
| 3.2 | **Camera is the default mode** — but this is an AI-first personal OS and private data store, not a social media app. Most users will come here to write notes, not take photos. | P1 | Bear Notes: opens to note list. Apple Notes: opens to last note. Making camera default is Instagram's pattern, but Kabuk's Vault is a private inbox, not Instagram. |
| 3.3 | **Capture preview has no editing tools** — no crop, rotate, filter, or annotation. | P2 | Instagram: full editing suite (crop, filter, adjust). Snapchat: stickers, text, drawing. |
| 3.4 | **Audio capture has no playback preview before saving** — you record, stop, name it, save. Can't listen back. | P1 | Voice Memos: playback immediately after stopping. Every audio app: preview before commit. |
| 3.5 | **Note composer has no auto-save** — pressing back without saving loses all content. Discard confirmation only shown when content exists, but still risky. | P1 | Apple Notes: auto-saves continuously. Bear: auto-saves on every keystroke. |
| 3.6 | **No way to access previous captures from the Vault tab** — it's a pure capture interface. To see your notes, you have to go to Apps → Notes. | P2 | Google Keep: grid of notes right on home. Apple Notes: note list is the home view. |
| 3.7 | **NOTE and AUDIO modes don't need the camera** but still show the camera viewfinder briefly before transitioning. | P3 | Best practice: mode should pre-determine the view layout, not show camera first. |
| 3.8 | **No AI organization feedback** — after capturing, the user doesn't see that the local LLM processed and tagged the content. | P1 | Google Photos: shows "Categorizing…" after upload. The AI action should be visible to build user trust. |

#### Recommendations
1. Change the default Vault mode to NOTE (aligns with private-inbox, AI-organization philosophy)
2. When camera is unavailable, show a useful fallback (note composer, image picker, or mode selection without camera)
3. Add auto-save to notes (save draft to knowledge store on every change)
4. Add playback to audio capture before saving
5. After any capture, show a brief "AI is organizing this…" indicator to communicate local LLM processing
6. Show recent vault items below the capture controls so the Vault feels like an inbox, not a dead end

---

### 4. Apps Tab (Launcher & Tools)

**What it does**: Bookmark grid, saved AI views, built-in mini-apps (Notes, Calendar, Contacts, Search, Files), developer console.

**Comparable apps**: iOS Home Screen, macOS Launchpad, Notion sidebar

#### What works well
- Section-based organization (Pinned, Saved Views, Tools, Developer) is logical
- Tools row with icon chips is clean and scannable
- Developer section with widget library introspection is useful for developers

#### Issues found

| # | Issue | Severity | Benchmark |
|---|-------|----------|-----------|
| 4.1 | **Calendar shows empty state: "No events yet — Ask the Calendar agent to create events"** — passive instruction that requires leaving the screen. No "Create Event" button. | P1 | Google Calendar: FAB to create event. Apple Calendar: inline "+" button. |
| 4.2 | **Contacts shows empty state: "No contacts yet — Ask the Contact agent to create contacts"** — same problem. Agent-first doesn't mean agent-only. | P1 | Apple Contacts: "+" button to add contact. Google Contacts: FAB. |
| 4.3 | **Saved Views section says "AI-generated views from chat will appear here when you save them"** but the save mechanism is TODO in the code. Dead feature. | P0 | Not shipping a feature that's prominently displayed but non-functional. |
| 4.4 | **Search mini-app exposes raw RDF triples** (subject, predicate, object) — incomprehensible to non-technical users. | P1 | Spotlight: shows formatted results in cards. Notion AI: shows structured, readable results. |
| 4.5 | **Files mini-app is a placeholder** — "Browse files saved by agents" with no content. | P2 | Should be hidden until functional, or show useful placeholder. |
| 4.6 | **Developer section is expanded by default** — shows widget library internals ("kabuk:core, 6 widgets, v1.0.0") that mean nothing to regular users. | P2 | Android: developer options are hidden by default, unlocked via 7 taps. iOS: no dev section in user-facing apps. |
| 4.7 | **Pinned Bookmarks section is empty with "Pin your favorite web apps and sites here"** — long instructions for a feature that needs a single action. | P3 | iOS home screen: intuitive add-to-home-screen flow. Chrome: bookmark bar auto-populates with frequently visited. |
| 4.8 | **"Settings" button in Apps tab is redundant** — Settings is already accessible from Explore tab. Inconsistent entry points. | P3 | iOS: Settings is always one place. Having it on two tabs is confusing. |

#### Recommendations
1. Add direct-action buttons to Calendar and Contacts ("+") — agent-first doesn't mean users can't also tap a button
2. Hide Saved Views section until the feature is actually implemented
3. Hide Developer section by default; unlock via settings toggle or long-press gesture
4. Replace raw triple search with a formatted knowledge store browser showing recognizable entities (notes, events, contacts)
5. Hide Files mini-app until it has content to show
6. Consolidate Settings access point to one location (Settings tab or profile/avatar menu)

---

### 5. Settings

**What it does**: Configuration hub for identity, AI provider, services, relays, data, and about.

**Comparable apps**: iOS Settings, Telegram Settings, Discord Settings

#### What works well
- Clean grouped section layout follows iOS Settings conventions
- Connection status indicators (green/red dots) for relays
- LLM configuration with connection test is thorough
- Local model management with download progress is well-executed

#### Issues found

| # | Issue | Severity | Benchmark |
|---|-------|----------|-----------|
| 5.1 | **Service provider configurations are not persisted** — they reset on app restart. The code has a TODO about this. | P0 | Every settings app: changes persist immediately. |
| 5.2 | **"Knowledge Store" and "Encryption" settings show "Coming Soon" dialog** — prominent settings that do nothing. | P2 | Don't show what doesn't work yet. |
| 5.3 | **Identity page has no QR code** for sharing npub — copying a long hex string is poor UX. | P2 | Telegram: QR code for adding contacts. Damus: QR code for npub sharing. |
| 5.4 | **No identity backup reminder** — users can generate a keypair and lose it. No seed phrase, no backup enforcement. | P1 | Every crypto wallet: mandatory backup flow with seed verification. |
| 5.5 | **LLM settings require manual save** — temperature/token changes aren't auto-applied. | P3 | Most settings apps: changes apply immediately. |
| 5.6 | **Relay management allows duplicate URLs** — no validation for existing relays. | P3 | Any list management: dedup on add. |

#### Recommendations
1. Persist service provider configs to knowledge store immediately
2. Hide "Coming Soon" items from the settings list
3. Add QR code to identity page for npub sharing
4. Add mandatory backup flow after keypair generation
5. Auto-save settings changes

---

### 6. Onboarding

**What it does**: 3-page welcome flow (Welcome → AI Config → Ready).

**Comparable apps**: Notion, Linear, Duolingo onboarding

#### What works well
- Step-by-step approach with skip option
- Inline LLM connection test provides immediate feedback
- Local model download with progress is integrated well

#### Issues found

| # | Issue | Severity | Benchmark |
|---|-------|----------|-----------|
| 6.1 | **No identity creation in onboarding** — users hit Settings later to discover they need a keypair. Identity is fundamental to the app. | P1 | Nostr clients: keypair generation is step 1 of onboarding. |
| 6.2 | **No back button on pages** — can only swipe back, not tap. | P3 | Most onboarding: back arrow on step 2+. |
| 6.3 | **1047 lines in one file** — not a UX issue, but impacts maintainability and bug frequency. | — | — |

#### Recommendations
1. Add identity (keypair) generation as step 2 of onboarding (before AI config)
2. Add back navigation buttons

---

## Cross-Cutting UX Issues

### 7. Navigation & Information Architecture

| # | Issue | Severity |
|---|-------|----------|
| 7.1 | **Quick Chat FAB appears on every tab** including Chat tab — redundant on its own tab. | P3 |
| 7.2 | **Settings accessible from 2 different tabs** (Explore + Apps) — inconsistent. | P3 |
| 7.3 | **Feed subscriptions live in Chat tab** instead of Explore — cross-tab confusion. | P1 |
| 7.4 | **4-tab structure tries to serve too many purposes** — Explore (social feed), Chat (AI + messaging), Create (camera + notes + audio), Apps (bookmarks + tools + dev console + settings). Each tab is overloaded. | P2 |

### 8. Accessibility

| # | Issue | Severity |
|---|-------|----------|
| 8.1 | **Only 1 Semantics widget found** in all 30 files. Most interactive elements lack accessibility labels. | P1 |
| 8.2 | **Dark theme only** — no light theme option, reducing accessibility for low-vision users. | P2 |
| 8.3 | **SF Pro Display font** is Apple-only — Android users get a system fallback with potentially different metrics. | P2 |
| 8.4 | **No dynamic type support** — text sizes are hardcoded. | P2 |

### 9. Empty States & Error Handling

| # | Issue | Severity |
|---|-------|----------|
| 9.1 | **5 screens with placeholders** shown prominently: Saved Views, Files, Calendar, Contacts, Knowledge Store/Encryption settings. | P1 |
| 9.2 | **Agent-only creation pattern** for Calendar and Contacts forces users through chat for basic CRUD. | P1 |
| 9.3 | **Generic error handling** — most async errors caught silently or show generic snackbar. | P2 |

---

## Competitive Comparison Matrix

| Feature Area | Kabuk Current | Best-in-Class | Gap |
|-------------|---------------|---------------|-----|
| **Feed UX** | Card feed with filter chips | Reddit (sort/filter/inline media) | Missing inline comments, sorting, infinity scroll |
| **Article Detail** | Floating bottom sheet, no back button | Twitter thread (full page, threaded) | Missing navigation, native comments, share sheet |
| **Search** | Single text field modal | Instagram Explore (grid + categories) | Missing categories, trending, suggestions |
| **AI Chat** | Streaming markdown, suggestion chips | ChatGPT (title, regenerate, branch, share) | Missing titles, regenerate, conversation management |
| **DM** | E2E encrypted, status indicators | Signal (reactions, reply, disappearing) | Missing reactions, reply-to, disappearing msgs |
| **Camera** | Full-screen viewfinder + capture | Instagram (filters, editing, multi-select) | Missing editing tools, filters |
| **Notes** | Markdown editor + tags | Apple Notes (rich text, auto-save, attachments) | Missing auto-save, attachments, folder organization |
| **Calendar** | Empty state only | Google Calendar (month view, FAB, invites) | Not functional |
| **Contacts** | Empty state only | Apple Contacts (list, detail, groups) | Not functional |
| **Settings** | iOS-style grouped list | iOS Settings (search, immediate persist) | Missing search, persistence broken |

---

## Priority Action Plan

### Immediate (P0 — Fix Now)
1. **Fix thread view navigation** — add back button, drag handle, or make it a full page route
2. **Persist service provider settings** to knowledge store
3. **Hide Saved Views section** until the feature is implemented
4. **Graceful camera fallback** — show mode selector or gallery when camera unavailable

### Short-term (P1 — Next Sprint)
5. **Move feed subscriptions** from Chat to Explore
6. **Hide agent internals** from user-facing messages (no "router", no URIs, no raw triple data)
7. **Add direct-action buttons** to Calendar and Contacts ("+")
8. **Add identity creation** to onboarding flow
9. **Add audio playback** preview before saving
10. **Add note auto-save**
11. **Add identity backup enforcement**
12. **Improve accessibility** — add Semantics widgets throughout

### Medium-term (P2 — Next Month)
13. **Simplify Explore app bar** — reduce to 2-3 actions
14. **Add conversation search** in Chat
15. **Consolidate "New DM/Channel/Contact"** into single compose action
16. **Hide Developer section** by default in Apps
17. **Add light theme** option
18. **Add cross-platform font** fallback
19. **Change Vault tab default** to NOTE mode

### Long-term (P3 — Backlog)
20. Add conversation titles and rename
21. Show markdown formatting as rich text, not toolbar
22. Add back button to onboarding pages
23. Remove redundant Quick Chat FAB from Chat tab
24. Consolidate Settings entry point

---

## Summary

Kabuk has strong architectural foundations (RDF triple store, Nostr integration, agent system, RFW dynamic UI) but the UX suffers from three systemic problems:

1. **Feature sprawl** — too many half-built features shown to users. Calendar, Contacts, Files, Saved Views, and Knowledge Store browser are all visible but non-functional. This creates a poor first impression.

2. **Agent-only interaction** — Calendar and Contacts force users to go through the AI chat for basic CRUD operations. Agent-first should mean agents are the *best* way to interact, not the *only* way. Users need direct-manipulation affordances too.

3. **Technical internals leaking** — raw URIs, agent names ("router"), RDF triples, widget library versions, and Nostr-specific terminology are visible throughout. The UI should be a polished abstraction layer, not a developer dashboard.

The highest-impact improvement would be **hiding unfinished features and technical internals** — this single change would make the app feel 50% more polished without writing any new code.
