# TradeTraxs Native iOS — Architecture

**Status:** Source of truth for the native iOS application.  
**Scope:** True native Swift app. Not Capacitor. Not WebView. Not the Next.js UI.  
**Audience:** Every engineer contributing to the iOS app.

If a PR conflicts with this document, either change the PR or update this document in the same PR with justification.

---

## Table of contents

1. [Core Principles](#1-core-principles)
2. [Folder Structure](#2-folder-structure)
3. [Layer Responsibilities](#3-layer-responsibilities)
4. [Dependency Rules](#4-dependency-rules)
5. [Naming Conventions](#5-naming-conventions)
6. [Design System Standards](#6-design-system-standards)
7. [Navigation Standards](#7-navigation-standards)
8. [Repository Standards](#8-repository-standards)
9. [Networking Standards](#9-networking-standards)
10. [Realtime Standards](#10-realtime-standards)
11. [Caching Standards](#11-caching-standards)
12. [Performance Budgets](#12-performance-budgets)
13. [Image Handling Standards](#13-image-handling-standards)
14. [Error Handling Standards](#14-error-handling-standards)
15. [Dependency Injection](#15-dependency-injection)
16. [Logging & Observability](#16-logging--observability)
17. [Configuration & Environments](#17-configuration--environments)
18. [Testing Philosophy](#18-testing-philosophy)
19. [Code Review Checklist](#19-code-review-checklist)
20. [Things That Are Never Allowed](#20-things-that-are-never-allowed)
21. [Simplicity Challenges](#21-simplicity-challenges)
22. [Foundation Roadmap](#22-foundation-roadmap)

---

## 1. Core Principles

1. **Performance is a feature.** Instant tab switches, disk-first paint, no blocking spinners when a snapshot exists.
2. **Native-first UX.** System navigation, gestures, haptics, sheets, keyboards. Never recreate web layouts.
3. **Backend is shared; UI is not.** Supabase + selected BFF routes are the platform. Screens are iOS-only.
4. **Simplest architecture that scales.** Prefer Apple defaults. Add libraries only when a measured gap appears.
5. **Clear ownership.** Every entity has one repository. Every screen has one primary ViewModel.
6. **Stale-while-revalidate.** Show cached content immediately; refresh silently.
7. **Retained tabs.** Tab roots stay alive. Remounting tabs is a bug.
8. **Contracts over coupling.** Share API/RPC meanings with web, never components or hooks.

### Why this section exists

Without explicit principles, teams reintroduce WebView habits, god-objects, and premature frameworks. Principles are the filter for every later decision.

---

## 2. Folder Structure

Target layout (Xcode project / SPM). Paths are conceptual; exact Xcode group names may mirror these folders.

```text
native-ios/
  README.md
  ARCHITECTURE.md                 ← this file

  TradeTraxs/                     ← app target (created when Xcode project lands)
    App/
      TradeTraxsApp.swift         ← @main
      AppDelegate.swift           ← push / lifecycle only if required
      CompositionRoot.swift       ← builds AppEnvironment
      DeepLinkRouter.swift

    Features/
      Auth/
      Home/                       ← Dashboard tab root
      Feed/
      Compose/
      Messaging/                  ← Inbox + threads
      Rooms/
      Social/                     ← Profile, follow graph
      Explore/
      Leaderboard/
      Notifications/
      Settings/
      Billing/
      each feature/
        Views/
        ViewModels/
        Coordinators/             ← optional; only when navigation is non-trivial
        Components/               ← feature-private UI

    Domain/
      Models/                     ← pure value types
      UseCases/                   ← write flows & multi-step rules
      Policies/                   ← TTL, prefetch, badge formula

    Data/
      Repositories/
      Remote/
        Supabase/
        BFF/                      ← Next.js API client
      Local/
        Persistence/              ← SwiftData (or Core Data if needed)
        Cache/
      Realtime/
        RealtimeHub.swift

    DesignSystem/
      Colors/
      Typography/
      Components/                 ← shared buttons, rows, empty states
      Spacing/
      Haptics/

    Platform/
      Auth/
      Push/
      Haptics/
      Linking/
      Keychain/

    Config/
      AppEnvironment.swift
      BuildConfiguration.swift
      Secrets.example.plist       ← never commit real secrets

  TradeTraxsTests/
  TradeTraxsUITests/
```

### Top-level folder responsibilities

| Folder | Responsibility |
|--------|----------------|
| `App/` | Process entry, DI composition, deep links, global scene |
| `Features/` | User-facing product verticals (UI + ViewModels) |
| `Domain/` | Pure models, use cases, policies — no SwiftUI, no I/O |
| `Data/` | Repositories, networking, persistence, realtime, caches |
| `DesignSystem/` | Visual language and reusable controls |
| `Platform/` | OS integrations (Keychain, Push, Links) |
| `Config/` | Environments, feature flags wiring, non-secret config |

### Why this section exists

A fixed tree prevents “dump everything in one target group” entropy and makes dependency rules enforceable in review.

---

## 3. Layer Responsibilities

```text
Views (SwiftUI / UIKit islands)
    ↓ intents
ViewModels / Stores
    ↓ use cases (writes) or repositories (reads)
Domain UseCases
    ↓
Repositories
    ↓
Remote (Supabase / BFF)  ·  Local (SwiftData)  ·  RealtimeHub
```

| Layer | May know | Must not know |
|-------|----------|---------------|
| Views | ViewModels, DesignSystem | Repositories, Supabase, BFF URLs |
| ViewModels | UseCases, Repositories (protocols), Models | SwiftUI layout details beyond presentation state; raw SQL |
| Domain | Models, Policies | SwiftUI, UIKit, URLSession, Supabase SDK |
| Data | Domain models, remote/local SDKs | Feature Views |
| Platform | OS frameworks | Feature business rules |

### Why this section exists

Layers stop networking and UI from fusing the way oversized web `page.tsx` files did.

---

## 4. Dependency Rules

### Allowed dependency direction

```text
App → Features → Domain
              ↘ Data → Domain
Features → DesignSystem
Features → Platform (sparingly; prefer ViewModel → Platform via protocols)
Data → Platform (e.g. Keychain for tokens)
App → everything (composition only)
```

### Import rules (enforce in code review)

1. `Features/A` must not import `Features/B` directly. Cross-feature navigation goes through `AppDestination` + coordinators / app router.
2. `Domain` must not import `Data`, `Features`, `DesignSystem`, or SwiftUI.
3. `DesignSystem` must not import `Features` or `Data`.
4. `Data/Repositories` expose **protocols** consumed by Features; Features depend on protocols, not concrete Supabase types.
5. No feature may import the Capacitor `/ios` project or any web package.

### Why this section exists

Dependency rules are how architecture survives growth. Without them, Feed will import Rooms will import Profile until compile times and coupling explode.

---

## 5. Naming Conventions

| Kind | Pattern | Example |
|------|---------|---------|
| Feature folder | Singular product name | `Messaging`, `Feed` |
| View | `*View` | `InboxView` |
| ViewModel | `*ViewModel` | `InboxViewModel` |
| Repository protocol | `*Repository` | `TradeRepository` |
| Repository impl | `Default*Repository` or `Supabase*Repository` | `SupabaseTradeRepository` |
| Use case | Verb phrase | `SendDirectMessage`, `TogglePostLike` |
| Model | Noun | `Trade`, `ConversationSummary` |
| DTO (network) | `*DTO` / `*Response` | `LeaderboardResponse` |
| SwiftUI errors shown to user | map via `UserFacingError` | — |

File names match primary type names (one primary type per file when practical).

### Why this section exists

Consistent names make navigation in large codebases automatic and keep PRs reviewable.

---

## 6. Design System Standards

- Own colors, type, spacing tokens under `DesignSystem/`.
- Prefer SF Symbols and system materials over custom icon packs unless brand-critical.
- Shared components: buttons, list rows, avatars, empty states, error banners, loading placeholders.
- Feature-specific visuals stay in `Features/*/Components`.
- **Do not** port web gradient shells as the default app chrome.
- Support Dynamic Type and reduce-motion where reasonable from day one.

### Why this section exists

A small design system prevents every feature inventing its own button and keeps the app feeling like one product.

---

## 7. Navigation Standards

### Structure

```text
Root
├─ Auth stack (logged out)
└─ Main tabs (logged in) — roots RETAINED
     ├─ Home
     ├─ Feed
     ├─ Create (compose entry)
     ├─ Messages
     └─ Profile
```

- Secondary flows (Rooms, Explore, Leaderboard, Settings, Notifications, Calendar, Trades) are **pushed stacks or sheets**, not extra always-on tabs (unless product later expands the tab bar intentionally).
- Use `NavigationStack` per tab.
- Cross-tab jumps and universal links go through `DeepLinkRouter` → typed `AppDestination`.
- Sheets for filters, pickers, light settings; `fullScreenCover` for composer and media viewer.

### Rules

1. Tab roots must not be destroyed on switch.
2. Views do not hard-code deep URL strings; they emit destinations.
3. Auth gating lives in the app router, not in random feature views.

### Why this section exists

Navigation mistakes (remounting tabs, URL soup in views) are the #1 reason native apps feel like wrapped websites.

---

## 8. Repository Standards

- One repository per aggregate/entity family (`TradeRepository`, `FeedRepository`, `InboxRepository`, …).
- Repositories own: fetch, cache read/write, invalidation hooks, in-flight dedupe.
- ViewModels call repositories/use cases — never Supabase client directly.
- Methods return domain models, not SDK types.
- Writes that need multi-step rules (like + notification API) go through **UseCases**.

### Minimal repository surface (example shape — not implementation)

- `func observe...` / `func load...` / `func refresh...` / `func mutate...`
- Prefer async/await.
- Cancellation must be respected (`Task` cancellation).

### Why this section exists

Repositories are the seam that keeps UI replaceable and networking testable. Skipping them recreates god-screens.

---

## 9. Networking Standards

### Two transports

| Transport | Use for |
|-----------|---------|
| **Supabase** (Auth, PostgREST, Storage, Realtime) | User-scoped CRUD under RLS; user RPCs |
| **BFF** (Next.js HTTPS + Bearer JWT) | Stripe, push registration, notification fan-out, follow-request admin paths, early-access/creator, AI, delete/export, aggregated leaderboard DTO |

### Rules

1. Always send `Authorization: Bearer <access_token>` to BFF.
2. Store tokens in Keychain only.
3. Coalesce identical in-flight GETs in repositories.
4. Prefer cursor/keyset pagination; ban unbounded list downloads.
5. Prefer aggregated DTOs for leaderboard, explore, feed engagement, inbox summaries.
6. Timeouts and retry only on idempotent reads; never blind-retry payments.

### Why this section exists

Clear transport split matches how the existing backend already works and prevents putting secrets on device.

---

## 10. Realtime Standards

`RealtimeHub` is the **only** owner of long-lived channels.

| Subscription | Lifetime |
|--------------|----------|
| Notifications (self) | Entire logged-in session |
| Self profile updates (entitlements) | Logged-in session |
| Feed inserts | While Feed tab visible (+ short grace) |
| DM thread + typing | While thread visible |
| Room messages / reactions / typing | While room visible |
| Detail like/comment channels | While detail visible |

### Rules

1. No per-cell channels.
2. Cap `in.(id,…)` filters (backend max 100 — stay under).
3. Hub auto-reconnects; features catch up via cursors, not full wipe.
4. Badge counts update from hub events + mark-read RPCs + push — single `BadgeStore` writer.

### Why this section exists

Unmanaged realtime caused channel sprawl on web. A hub makes lifetime explicit and reviewable.

---

## 11. Caching Standards

### Strategy: Partial offline + stale-while-revalidate

| Tier | Holds |
|------|-------|
| Memory | Hot tab state, decode buffers, LRU profiles/threads |
| Disk (SwiftData) | Self profile, accounts, trade window, inbox list, last N messages for recent threads, notifications page, feed page 1, entitlements |
| Disk (images) | Image pipeline disk cache |
| Keychain | Auth tokens, installation id |

### Do not persist

- Unbounded public trades for leaderboard
- Full lifetime trade history by default
- Other users’ private data
- Secrets from BFF beyond user JWT

### Soft TTLs (starting points; tune with metrics)

| Data | Soft TTL |
|------|----------|
| Feed page 1 | 30–60s |
| Inbox | 15–30s |
| Trades window | 45–120s |
| Leaderboard DTO | 60–90s |
| Explore | ~5m |
| Entitlements | Until realtime/profile refresh |

Sign-out clears Keychain, local DB snapshots, and image cache for the user.

### Why this section exists

Caching policy is product UX. Without it, every screen invents ad-hoc dictionaries and TTLs.

---

## 12. Performance Budgets

| Budget | Target |
|--------|--------|
| Cold start to interactive shell | ≤ 2.0s on recent iPhone, typical network |
| Tab switch | ≤ 100ms perceived (retained roots; no full remount) |
| Feed first paint from disk | ≤ 300ms after tab select |
| Scroll | 60fps target on Feed/chat; profile on Instruments if broken |
| Image memory | Hard cap via pipeline; downsample list thumbs |
| Main thread | No network decode or large JSON parse on main |

### Feature rules every PR must follow

1. Never block first paint on optional widgets.
2. Never download full trade history on launch.
3. Never download raw leaderboard trade dumps.
4. Prefetch next page / next images only for the visible tab.
5. Cancel work when views disappear.
6. Use UIKit list islands if SwiftUI `List` cannot hold 60fps for Feed/chat.

### Why this section exists

Performance budgets turn “feels fast” into enforceable review criteria.

---

## 13. Image Handling Standards

- One shared image pipeline for the app.
- List/grid: decode at display size; never full-resolution in cells.
- Prefetch for oncoming cells on Feed/profile grids.
- Viewer: full-res, paging, interactive dismiss.
- Prefer existing CDN/transform URL conventions from backend.
- Avatars and content images share pipeline config with different size presets.

### Why this section exists

TradeTraxs is media-heavy. Image handling mistakes dominate jank and memory jetsam.

---

## 14. Error Handling Standards

- Domain/repo errors are typed (`NetworkError`, `AuthError`, `ValidationError`, …).
- ViewModels map to `UserFacingError` (title/message/action).
- Do not show raw Postgres/HTTP strings to users.
- Optimistic updates allowed for likes, send message, mark read — always with rollback.
- Auth failures trigger session refresh once; then hard auth gate.
- Logging: log underlying error; UI shows friendly copy.

### Why this section exists

Consistent errors prevent “silent failure” and “alert spam” extremes.

---

## 15. Dependency Injection

- `CompositionRoot` builds a single `AppEnvironment` at launch.
- Pass dependencies via initializers to ViewModels/Repositories.
- Expose a minimal set through SwiftUI `Environment` (environment, theme, badge store).
- **No** runtime service-locator containers (Swinject-style) in v1.
- Tests swap fakes at the composition root.

### Why this section exists

Initializer DI is enough for this team size and keeps compile-time safety without framework tax.

---

## 16. Logging & Observability

| Concern | Standard |
|---------|----------|
| Logging | `os.Logger` with subsystems per layer (`auth`, `feed`, `realtime`, …) |
| Crash | One provider (Crashlytics or Sentry) |
| Analytics | One product analytics tool; privacy review before shipping |
| Breadcrumbs | Attach critical navigation + API failures to crash reports |

Do not log tokens, passwords, or PII payloads.

### Why this section exists

One logging story beats every feature inventing `print`.

---

## 17. Configuration & Environments

| Environment | Purpose |
|-------------|---------|
| Debug | Local/dev Supabase + BFF as configured |
| Staging | Pre-prod API |
| Production | App Store |

- Bundle IDs / schemes differ per env as needed.
- Secrets via CI/xcconfig — never committed.
- Feature flags: remote when available; local overrides in Debug only.
- OAuth redirect and universal links documented beside config.

### Why this section exists

Environment mistakes ship debug endpoints to production. Make the matrix explicit early.

---

## 18. Testing Philosophy

| Layer | Test approach |
|-------|----------------|
| Domain use cases | Unit tests, no I/O |
| Repositories | Unit tests with fake remote/local |
| ViewModels | Unit tests with fake repositories |
| Critical UI | Few UI tests (auth, tab smoke, compose happy path) |
| Performance | Manual Instruments gates on Feed/chat before major releases |

Do not chase 100% UI coverage. Prefer fast unit tests on money paths: auth, send message, save trade, entitlements.

### Why this section exists

Testing the wrong layer wastes time; testing domain/repo catches the bugs that matter.

---

## 19. Code Review Checklist

Reviewers verify:

- [ ] Dependencies point inward (Features ↛ Features; Domain has no I/O)
- [ ] No Supabase/BFF calls from Views
- [ ] No unbounded list fetches
- [ ] Tab retention preserved
- [ ] Cache/SWR behavior considered
- [ ] Realtime lifetime justified (hub-managed)
- [ ] Images go through pipeline
- [ ] Errors mapped to user-facing copy
- [ ] No secrets committed
- [ ] Tests for non-trivial use cases
- [ ] Matches Performance Budgets

### Why this section exists

Checklists encode architecture into daily practice.

---

## 20. Things That Are Never Allowed

1. WebViews or Capacitor as the product UI.
2. Importing or wrapping the Next.js app inside iOS.
3. Sharing React components, hooks, or CSS with iOS.
4. Fetching full trade history on launch.
5. Downloading all public trades for leaderboard/charts.
6. Creating a Realtime channel per table cell or per like row.
7. Remounting tab roots on every tab switch.
8. Storing JWT/session secrets in UserDefaults or files.
9. Calling service-role keys from the device.
10. Blocking first paint on optional modules (popular rooms, promos, analytics charts).
11. `print` debugging left in production paths.
12. Feature ↔ feature hard imports (use destinations).
13. God-view-models that own networking + navigation + persistence.
14. Premature micro-frameworks (global TCA, Realm Sync, custom ORM) without a written ADR.

### Why this section exists

A short ban list prevents the exact failure modes already seen in the web/WebView era.

---

## 21. Simplicity Challenges

This architecture intentionally **rejects** complexity that is easy to over-buy:

| Temptation | Decision | Simpler alternative |
|------------|----------|---------------------|
| TCA everywhere | Not default | MVVM + use cases; adopt TCA later for one state machine if needed |
| GRDB on day one | Not default | SwiftData snapshots; escalate only if SQL needs appear |
| Full offline sync engine | No | Partial offline SWR |
| Everything through BFF | No | Supabase RLS for normal CRUD |
| Everything direct to Supabase | No | BFF for secrets & fan-out |
| Multi-analytics + multi-crash tools | No | One of each |
| Clean/VIPER ceremony | No | Features + Domain + Data |
| Shared TS package inside the app | No | Shared **contracts** (OpenAPI/schema docs) |

If a proposal adds a framework, require: problem statement, alternative using Apple defaults, and rollback plan.

### Why this section exists

Self-challenge keeps the foundation honest. Complexity must earn its place.

---

## 22. Foundation Roadmap

Ordered work **after** this document is accepted. Still no product features until the shell exists.

1. **Sign-off** on this `ARCHITECTURE.md`.
2. **Create Xcode project** matching folder structure (empty feature folders OK).
3. **CompositionRoot + AppEnvironment** with fakes.
4. **AuthSession** (Keychain) + login placeholder.
5. **Main tab shell** with retained empty roots.
6. **DesignSystem** tokens + 3–5 primitives.
7. **BFF client + Supabase client** wiring (no screens).
8. **RealtimeHub + BadgeStore** stubs.
9. **SwiftData stack** empty models for snapshots.
10. **DeepLinkRouter** destination enum aligned with push/universal links.
11. Then feature development order: Home/Trades → Notifications → Messaging → Feed → Compose → Profile → Rooms → Explore/Leaderboard.

---

## Document control

| Field | Value |
|-------|-------|
| Owner | iOS lead / staff architect |
| Update process | PR with rationale; mention in review |
| Related | Existing backend under repo root (`supabase/`, `app/api/`); Capacitor `/ios` is out of scope |

*End of architecture source of truth.*
