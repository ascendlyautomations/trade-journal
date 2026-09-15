# TradeTraxs Native iOS — Final Release Audit

**Audit date:** 2026-09-15  
**Scope:** `native-ios/` + web/BFF/Supabase paths consumed by the native app  
**Method:** Read-only inspection of current repository; **one** Release `xcodebuild` (`-configuration Release -destination 'generic/platform=iOS Simulator'`) → **BUILD SUCCEEDED** (includes `-validate-for-store` on app bundle).  
**No code changes were made during this audit.**

---

## Executive summary (one page)

| Metric | Value |
|--------|--------|
| **Overall release grade** | **B−** |
| **App Store readiness** | **74%** |
| **Submit today?** | **No** — not until production backend/migrations, archive secrets, and App Store Connect IAP/push are verified on a TestFlight build |
| **P0 (blocks submission / ship risk)** | **3** |
| **P1 (fix before submit if possible)** | **6** |

### Verdict

TradeTraxs native is **architecturally shippable**: Release builds compile and validate for store; production BFF default is `https://www.tradetraxs.com`; Backend V2 RPC bootstrap flags default **ON** in Release; account deletion, Sign in with Apple, StoreKit 2 + server sync, UGC report flows, and session cache teardown on logout are implemented in code. The **ProfileID duplicate-key crash in Room Members** is **fixed** (`ProfileDictionaryByID` + layered merge in `RoomMembersViewModel`).

**Blockers are mostly operational and configuration**, not missing features: (1) **Release archives hard-fail without Supabase client secrets** in the bundle build pipeline; (2) **production Supabase must run the full September 202609* migration set** (including broker identity + profile tab reels RPCs) before native builds that depend on those contracts ship; (3) **TraxPro IAP** requires live App Store Connect products matching `TraxProProductConfiguration` — code is present but products are documented as placeholders until ASC is wired.

### Top remaining risks

1. **Production migration parity unknown from repo alone** — 52 migrations dated `202609*` including broker execution identity (`20260915140000_broker_execution_user_fill_identity.sql`) and profile reels tab RPC (`20260915120000_rpc_v1_profile_tab_reels_linked_trade.sql`). Native + BFF broker import assume server schema/RPCs exist.
2. **Release `fatalError` if Supabase not configured** — `AppConfigurationValidator.assertReadyForLaunch` traps Release builds missing `Secrets.plist` / env injection (`TradeTraxs/Config/Secrets.example.plist` documents pipeline).
3. **Residual `Dictionary(uniqueKeysWithValues:)` on `ProfileID`** in Explore/Messages/Leaderboard hydration — same crash class as Room Members if Supabase ever returns duplicate profile rows (Room path fixed; others not).
4. **Minimum OS iOS 18.0** (`IPHONEOS_DEPLOYMENT_TARGET = 18.0` in `project.pbxproj`) — valid for submission but excludes all iOS 17 devices; confirm intentional product decision.
5. **TraxPro on iOS** — StoreKit 2 + `/api/apple/subscription/sync` + DB tables exist; **IAP product IDs default to** `com.tradetraxs.traxpro.{monthly,sixmonth,yearly}` until Info.plist overrides — must exist in ASC and be sandbox-tested.
6. **Rithmic** — correctly **gated**: `showConnectUi` only when `apiEnvironment === "test"` (`app/api/integrations/rithmic/connect/route.ts` GET). Not an App Store blocker if UI hidden in production.

### Minimum work before submission

1. Apply and verify all pending Supabase migrations on **production** (especially Sept 14–15 broker + profile tab RPCs).
2. Configure **Release archive secrets** (Supabase URL + anon key; optional `API_BASE_URL` only if not using default production BFF).
3. App Store Connect: **IAP subscription group + 3 products**, push certs, associated domains, Sign in with Apple app ID configuration.
4. TestFlight pass using **manual test matrix** (Section 45) — especially Room Members, broker Tradovate import, IAP purchase/restore, account deletion, logout cache isolation.
5. **P1:** Harden Explore/Messages profile dictionaries (duplicate-safe merge) if any TestFlight crash logs show duplicate `ProfileID`.

---

## 1. Release build / archive readiness

### Evidence

| Item | Finding | Source |
|------|---------|--------|
| Version | Marketing **1.0**, build **9** | `TradeTraxs.xcodeproj/project.pbxproj` |
| Bundle ID | `com.tradetraxs.TradeTraxs` | `project.pbxproj` |
| Deployment target | **iOS 18.0** | `project.pbxproj` |
| Debug entitlements | APNs **development** | `TradeTraxs/App/TradeTraxs.entitlements` |
| Release entitlements | APNs **production** | `TradeTraxs/App/TradeTraxs-Release.entitlements` |
| Sign in with Apple | Enabled (Default) | Both entitlements plists |
| Associated domains | `applinks:www.tradetraxs.com`, `applinks:tradetraxs.com` | Entitlements |
| URL scheme | `tradetraxs://` (OAuth/deep link) | `Info.plist` `CFBundleURLTypes` |
| Usage descriptions | Camera, microphone, photo library | `Info.plist` |
| Background modes | `remote-notification` | `Info.plist` |
| Encryption export | `ITSAppUsesNonExemptEncryption` = false | `Info.plist` |
| Privacy manifest | Collected data types declared (email, name, user ID, device ID, photos/video, audio, UGC, search, financial info, purchase history); UserDefaults reason CA92.1 | `App/PrivacyInfo.xcprivacy` |
| Production BFF default | `https://www.tradetraxs.com` | `Config/AppConfiguration.swift` |
| Build lane | Release → `BuildConfiguration.production` | `Config/BuildConfiguration.swift` |
| Release compile | **BUILD SUCCEEDED** + validate-for-store | Audit build 2026-09-15 |

### Release vs Debug

- **DEBUG** probes (`RoomMembersLoadProbe`, feed/profile probes, login A/B UI) wrapped in `#if DEBUG` — e.g. `LoginView.swift` UITest controls only in DEBUG.
- **Release** uses `TradeTraxs-Release.entitlements` (production APNs).
- **Production fatal paths:**
  - `AppConfigurationValidator.assertReadyForLaunch` → `fatalError` if Supabase URL/anon key missing in **production** lane (`Config/AppConfigurationValidator.swift:36-42`).
  - `DataEnvironment.make` → `fatalError` if `NetworkingEnvironment` nil in production launch (`Data/DataEnvironment.swift:169-170`).
  - `AppEnvironment.networking` → `preconditionFailure` if accessed before deferred bootstrap (`Config/AppEnvironment.swift:30-32`).

### Archive / upload risks

| Risk | Severity | Notes |
|------|----------|-------|
| Missing `Secrets.plist` in CI/archive | **P0** | Documented in `Secrets.example.plist`; Copy Secrets build phase |
| Custom `API_BASE_URL` pointing to localhost | Low if unset | Default is production BFF for all lanes |
| No `NSAppTransportSecurity` exceptions in Info.plist | Good | HTTPS-only default |
| iOS 18 minimum | **P1 product** | Excludes iOS 17 users |
| No committed real secrets | Good | Only `Secrets.example.plist` in repo |

### NEEDS MANUAL VERIFICATION

- Distribution signing certificate + App Store provisioning profile for `com.tradetraxs.TradeTraxs`.
- Production `Secrets.production.plist` or CI env vars present on **archive** machine.
- App Store Connect app record linked to bundle ID.

---

## 2. Crash / runtime safety audit

### ProfileID duplicate crash (recent)

**Status: FIXED in Room Members path.**

```245:250:native-ios/TradeTraxs/TradeTraxs/Features/TradeRooms/Members/RoomMembersViewModel.swift
let embeddedProfiles = activeRows.map(\.profile)
let profileByID = ProfileDictionaryByID.build(embeddedProfiles, fetchedProfiles) { ... }
```

- **Root cause:** `fetchedProfiles + activeRows.map(\.profile)` fed to `Dictionary(uniqueKeysWithValues:)` — same ID in batch fetch and embedded membership profile (e.g. owner, or “Unknown User” refetch).
- **Rule:** Embedded first, **network/fetched overwrites** (`ProfileDictionaryByID.swift`).
- **Adjacent fix:** `SessionProfileStore.merge` now uses `ProfileDictionaryByID.build(a, b)` (`SessionProfileStore.swift:113-117`).

### Same crash class elsewhere (ProfileID)

Still using `Dictionary(uniqueKeysWithValues:)` on profile arrays:

| Location | Risk if duplicate API rows |
|----------|----------------------------|
| `ExploreProfileHydration.swift:114` | **Medium** |
| `ExploreViewModel.swift` (394, 532, 585) | **Medium** |
| `SuggestedTradersViewModel.swift` (202, 260, 332) | **Medium** |
| `MessagingBootstrap.swift:53` | **Medium** |
| `LeaderboardSessionStore.swift:98` | **Medium** |
| `ActivityInboxStore.swift` (95, 186) | Low (notification IDs) |
| `FeedBootstrap.swift:305` | Feed item IDs |
| `CalendarViewModel.swift:579` | Trade IDs |

**P1:** Explore + Messages bootstrap are high-traffic; recommend duplicate-safe merge before wide TestFlight if crashes appear.

### Other production fatals

| Site | Reachability |
|------|----------------|
| `AppConfigurationValidator` Release missing Supabase | Launch only — **intentional guard** |
| `FeedInlineVideoSurface` “Expected AVPlayerLayer” | Layer type mismatch — should not hit if view hierarchy correct |
| `init(coder:)` fatalError in UIKit bridges | Storyboard misuse — N/A if programmatic SwiftUI |
| `DefaultContentReportRepository` precondition | Only if misconfigured DI |

### Force unwraps / try!

Not exhaustively counted (~thousands of `!` in SwiftUI). **No blanket P0** — spot checks show broker/AI paths use `try?` or user-facing errors in ViewModels. **Recommendation:** watch TestFlight crash logs for `NativeDictionary` and decoding failures.

---

## 3. Authentication / session lifecycle

### Flow (code)

- **Providers:** Email/password, Google OAuth, Apple (`AppleSignInProvider`, nonce in `AppleSignInNonce.swift`, `SocialSignInButtons.swift`).
- **Storage:** Keychain via `SecureCredentialStore` / `TokenStore`.
- **Bootstrap:** Backend V2 session RPC when `backendV2.session` enabled (production default ON).
- **401 / refresh:** Handled in networking layer (Supabase session + BFF Bearer) — verify on device.
- **Logout / account switch:** `AuthenticationCoordinator` → `SessionScopedCaches.invalidate` (`SessionScopedCaches.swift`) clears messages, feed, profile, rooms, disk caches, images, realtime hub, uploads, billing entitlement, broker eligibility store, local reminders.

### Cross-account privacy

**Designed teardown is broad** — includes `GlobalUploadCoordinator.shared.invalidateForSessionChange()`, `BackendV2BootstrapDiskCache.clearAll()`, vault store, detail cache.

**NEEDS MANUAL VERIFICATION:** No prior-user feed/profile/trades visible after logout → login as different user on one device.

### Deep links

- URL scheme `tradetraxs://` in Info.plist; associated domains for universal links.
- Routing via `NavigationCoordinator` / notification routing — **manual test** cold launch vs warm.

---

## 4. Apple Sign In

| Check | Status |
|-------|--------|
| Entitlement | Present |
| Nonce + SHA256 | `SocialSignInButtons.swift`, `AppleSignInProvider.swift` |
| Cancel / error | `LoginViewModel.handleAppleSignInCancelled/Failure` |
| Account deletion copy | `SettingsAccountViewModel` mentions Sign in with Apple implications |
| Tests | `AppleSignInPhase1Tests.swift` |

**NEEDS MANUAL VERIFICATION:** First-login display name capture; returning user; production Services ID / redirect if web leg involved.

---

## 5. Subscriptions / Trax Pro

### Architecture (verified in repo)

- **StoreKit 2:** `StoreKitSubscriptionService.swift` — load products, purchase, restore, transaction listener, sync to BFF.
- **Product IDs:** `TraxProProductConfiguration.swift` — defaults `com.tradetraxs.traxpro.monthly|sixmonth|yearly`; overridable via Info.plist keys.
- **Server sync:** `AppleSubscriptionSyncClient.swift` → `POST /api/apple/subscription/sync`.
- **Server notifications:** `app/api/apple/subscription/notifications/route.ts`, migrations `20260909180000_*`, `20260909190000_*`.
- **Entitlement resolver:** `TraxProEntitlementResolver.swift` — Apple, Stripe, manual, early access, creator.
- **UI policy:** `SubscriptionPresentationPolicy.swift` — **no external checkout URLs**; Stripe users see “billing managed outside the App Store”; Apple IAP section only when `showsApplePurchaseOptions`.
- **Compliance tests:** `SubscriptionComplianceTests.swift`, `ProEntitlementResponseSanitizer.swift` strips “stripe checkout” from API messages shown in app.

### Apple digital goods compliance

- Native **does not** open Stripe checkout for digital TraxPro on iOS (Settings subscription uses StoreKit when on Free plan).
- **Restore purchases** exposed when appropriate (`SettingsSubscriptionViewModel.showsRestorePurchases`).

### App Store Connect (not in repo)

**MUST DO BEFORE SUBMISSION (IAP):**

- Create subscription group + 3 auto-renewable products matching IDs.
- Sandbox purchase + restore + server sync row in `apple_subscriptions`.
- Apple Server Notifications URL → production BFF `/api/apple/subscription/notifications`.
- Paid Apps Agreement, tax/banking.

**Grade: Subscription readiness C+** (code A−, configuration incomplete).

---

## 6. Account creation / onboarding

- **Gate:** `ProfileOnboardingGateStore` / bootstrap flags `onboarding_completed` (migration `20260901160000_grandfather_active_profiles_onboarding_completed.sql`).
- **Username / profile setup:** Profile onboarding flows in Features/Profile (inspect on device).
- **Apple missing name:** Handled server-side + profile edit — **manual test**.

---

## 7. Account deletion

| Check | Evidence |
|-------|----------|
| Settings entry | `SettingsHomeModel` → Account → `SettingsAccountView` |
| BFF | `DefaultAccountRepository` → `POST /api/delete-account` |
| Server pipeline | `deleteUserAdmin` with Stripe optional cleanup (`app/api/delete-account/route.ts`) |
| Push unregister | `CompositionRoot` → `prepareAccountDeletion` → `PushNotificationCenter.unregisterForAccountDeletion` |
| Local teardown | `AuthenticationCoordinator.deleteAccount` uses `useAccountDeletionTeardown: true` |
| Copy | TraxPro trial, Stripe, Apple called out in tests `AccountDeletionExperienceTests.swift` |

**NEEDS MANUAL VERIFICATION:** End-to-end delete on staging/production; confirm broker credentials and storage objects removed per `deleteUserAdmin`.

---

## 8. Settings

### Current hierarchy (`SettingsHomeModel.swift`)

- **Account:** Account, Profile, Privacy, Notifications  
- **TradeTraxs:** Subscription, Trading Accounts, Withdrawals, Referrals  
- **Personal:** Vault, Appearance  
- **Support:** Support, About  
- **Legal:** Terms, Privacy, Community Guidelines  

**Broker integrations:** Not top-level; nested under **Trading Accounts** → `BrokerIntegrationsView` (`SettingsTradingAccountsView.swift`).

**Also routable:** `SettingsRoute.brokerIntegrations` → `SettingsDestinationView`.

No Security row on home (password likely under Account) — consistent with recent cleanup.

**NEEDS MANUAL VERIFICATION:** Every row navigates to a non-placeholder screen; legal URLs load.

---

## 9. Dashboard

- Backend V2 **`backendV2.dashboard`** ON in production defaults.
- Components: equity hero, filters, check-in, broker import card, insights, charts (`Features/Home/Dashboard/`).
- **Broker import:** Shared eligibility via `BrokerImportEligibilityStore` + BFF eligibility route.
- **Cache:** Session stores + bootstrap appliers — mutation via `TradeJournalMutationStore`, broker import invalidation hooks.

**NEEDS MANUAL VERIFICATION:** Filter combinations, multi-account, post-import metrics refresh.

---

## 10. Calendar

- Month + **Year view** (`CalendarYearView.swift`, `CalendarViewModel`).
- Backend V2 **`backendV2.calendar`** ON.
- Trading day semantics: ET-oriented aggregators (`TradingCalendarAggregator`, reminders use `America/New_York`).

**NEEDS MANUAL VERIFICATION:** Month vs Year P&L parity for same account/mode filters; imported trades; fees.

---

## 11. Trades

- List: `TradeHistoryViewModel` + Backend V2 trades list flag ON.
- Add/edit/delete: mutation stores + navigation probes in tests.
- Broker imports: enrichment preservation server migrations (`20260914290000_trades_broker_enrichment_status.sql`) — **requires prod migration**.
- Review Imported Trades flow in broker UX.

---

## 12. Global background upload

- **Coordinator:** `GlobalUploadCoordinator.swift` — trade, post, reel, story, achievement pipelines.
- **Session change:** `invalidateForSessionChange()` from `SessionScopedCaches`.
- **DEBUG** diagnostics only in `#if DEBUG`.

**NEEDS MANUAL VERIFICATION:** Dismiss composer, background upload continues; logout cancels or isolates in-flight jobs.

---

## 13. Media pipeline / storage

- **Images:** Tiered cache, transforms, coalescing (`TieredImageCache`, `ImageLoadCoalescer`).
- **Video:** `MediaVideoPreparation`, H.264/AAC, poster frames (`VideoPosterFrameLoader`, feed inline surfaces), player budget in `FeedVideoPlaybackCoordinator`.
- **Egress risk:** Prefetch + disk cache — monitor Supabase storage/CDN bills post-launch (**P2**).

---

## 14. Feed

- RPC bootstrap `backendV2.feed` ON; block filter migration `20260904120000_rpc_v1_feed_bootstrap_block_filter.sql`.
- Realtime hub incremental updates.
- **Block filtering:** `FeedBlockedAuthorsFilter` cleared on logout — stale cache risk if block while offline (**manual test**).

---

## 15. Profile

- Backend V2 profile bootstrap ON.
- Duplicate hydration crash **fixed** on Room Members; profile tab uses RPC + caches.
- **Instant error flash:** No explicit comment in code from grep — **manual verify** other-profile cold load.

---

## 16. Explore / Leaderboards

- **Old full corpus:** `DefaultLeaderboardRepository` throws retired message; rankings via `rpc_v1_leaderboard_*` when `backendV2.leaderboard` ON (production default).
- Explore people hydration — **duplicate ProfileID risk** (Section 2).

---

## 17. Messages / DMs

- `backendV2.messages` + `messageThreads` ON.
- Bootstrap: `MessagingBootstrap.swift` — profile dict uses `uniqueKeysWithValues`.
- Realtime + inbox stores; logout invalidates `MessagesInboxStore`, `ConversationThreadSessionStore`.

---

## 18. Activity / notifications

- Activity bootstrap flag ON.
- **Push:** `PushNotificationCenter`, background mode, production APNs in Release entitlements.
- **Local reminders:** Daily check-in + trade import 11:15 / 16:00 ET (`TradeImportReminderScheduler.swift`); cancelled on logout in `SessionScopedCaches`.

**NEEDS MANUAL VERIFICATION:** Tap routing cold/foreground; badge counts; Settings toggles.

---

## 19. Trade Rooms (deep)

| Requirement | Code evidence |
|-------------|---------------|
| Owner Room Info = member-facing read-only | `RoomInfoView` — name, picture, members, description, invite, owner, link to settings; **no owner-only edit** on this screen |
| Owner no Leave on Settings | `RoomSettingsView` — Leave section only `if !viewModel.isOwner` |
| Member can Leave | Member section + confirmation dialog |
| Owner Delete from Settings | `canDeleteRoom` + Delete in Danger Zone |
| Members hydration | `RoomMembersViewModel` + duplicate-safe profiles |
| Member count authority | `RoomMemberCountSync`, migration `20260906250000_room_active_member_count_authority.sql` |

**NEEDS MANUAL VERIFICATION:** Realtime message delivery, channel switch, join/leave, official vs user rooms.

---

## 20. Channel management

- `ManageRoomChannelsView` — Edit/Done, expandable rows, `allow_members_chat` → Everyone / Owners Only, server `setChannelPostingPermission`.
- **NEEDS MANUAL VERIFICATION:** Gesture conflicts, persistence, owner-only enforcement server-side.

---

## 21. Tag management

- `ManageRoomTagsView` — TAGS | Edit, delete flow, `deleteMemberTag`.
- Migrations: `20260906240000_room_member_tags.sql`.

---

## 22. Stories

- Editor: `StoryEditorViewModel` — text, media, upload via global coordinator.
- **Pinch resize:** **NEEDS MANUAL VERIFICATION** on device (tests in `StoryEditorTests.swift` exist).

---

## 23. Reels / clips

- **Constraint fix:** `20260914210000_drop_reels_trade_caption_check.sql` drops `reels_trade_caption_check`.
- Native: `ReelDraft.swift` documents caption independent of linked trade; feed select includes both fields (`DefaultFeedRepository.swift`).

---

## 24. Achievements

- Create/detail/feed/profile paths; payout achievements in domain models.
- **NEEDS MANUAL VERIFICATION:** Legacy tier UI not shown (grep fixtures DEBUG-only).

---

## 25. Vault

- Folders, batch RPC, session store cleared on logout (`data.vaultStore.removeAll()`).
- RLS via Supabase — **server** must enforce private vault (**audit migrations** `20260906220000_vault_items_folders.sql`).

---

## 26–28. Broker integrations

### Architecture rule: thin BFF client ✅

- Swift calls `/api/integrations/*` only (`DefaultBrokerIntegrationRepository.swift`).
- No R|Protocol in iOS.

### Tradovate (V1 manual import)

- OAuth via `ASWebAuthenticationSession`, deep link `tradetraxs://`, BFF token encryption, account link, sync endpoint — **CODE COMPLETE**.
- **PRODUCTION-USER PROVEN:** **NEEDS MANUAL VERIFICATION** on TestFlight.

### Rithmic

| Stage | Status |
|-------|--------|
| Server protocol foundation | **CODE COMPLETE** (`lib/integrations/rithmic/*`, migrations `20260914310000_*`, etc.) |
| Test environment | **TEST-ENVIRONMENT PROVEN** (connect UI gated to test — `showConnectUi` only when `apiEnvironment === "test"`) |
| Real-fill / production user | **NOT YET PROVEN** — `productionUserAuthConfirmed` env-gated |
| Native UI in production | **Hidden** when `showConnectUi == false` |

**Not an App Store blocker** if production users only see Tradovate + disabled Rithmic connect.

### Broker import UX entry points

- Dashboard card, Settings → Trading Accounts → Broker Integrations, eligibility store (no polling in UI copy audit — **verify strings**).

---

## 29–30. Privacy / security

| Check | Finding |
|-------|---------|
| Service role in iOS | **Not embedded** — `AppConfiguration` documents anon key only |
| Stripe secret in iOS | **Not found** — server-only |
| Broker passwords in Swift | Sent to BFF over HTTPS only; not stored plaintext in UserDefaults (credentials server-side encrypted) |
| Keychain | Session tokens |
| RLS / BFF auth | `getRouteUser` on API routes |
| Logs | DEBUG probes avoid tokens; **NEEDS MANUAL VERIFICATION** for production OSLog volume |

**P2:** Ensure no PII in production NSLog from broker debug (grep `BrokerIntegrationDebugLog` — use only on failures).

---

## 31. Supabase / database

- **52+ September migrations** — critical path includes broker integrations, apple subscriptions, feed block filter, room tags, vault, RPC bootstraps.
- **RELEASE BLOCKER if prod DB behind:** native 1.0 build + BFF expect RPCs/tables from `20260915120000` and `20260915140000` among others.
- **viewerSyncState:** flag exists but **NOT** in `productionShippedFlags` — reconciliation RPC optional post-launch (**P2**).
- Advisor warnings / duplicate indexes — treat as **post-launch hardening** unless specific query breaks prod.

---

## 32. Network performance

- Single-flight: `RepositoryRequestFlight`, `SessionProfileStore` in-flight coalescing, `BackendV2SingleFlight`.
- **Observed pattern (logs):** duplicate RoomMembers/startup requests — **P2** “feels frozen”, not crash.
- Profile batch: `SessionProfileStore.profiles(ids:)` dedupes IDs with `Set`.

---

## 33. Cache architecture

- Session + disk JSON caches per domain; coordinated invalidation on logout (Section 3).
- Mutation stores for trades, accounts, content, follow.
- **Risk:** Block/privacy changes without refresh — **manual test**.

---

## 34. Realtime

- `RealtimeHub` stopped on logout (`SessionScopedCaches` → `realtimeHub.stop()`).
- Room/DM/feed channels — screen-scoped subscriptions expected — **NEEDS MANUAL VERIFICATION** for duplicate subscribe on navigation.

---

## 35. AI features

- Trade analyst + psychology coach via BFF (`DefaultAIRepository.swift`).
- **Em dash normalization:** `AIGeneratedTextNormalizer.swift` mirrors `lib/normalizeAIGeneratedText.ts`; applied to AI responses only (tests in `TradeAIExperienceTests.swift`).
- **Disclaimer:** verify UI copy on AI screens — **manual**.

---

## 36. Accessibility

- `ExperienceAccessibility.minTouchTarget` used in places (e.g. login).
- **P2:** Full VoiceOver pass not evidenced in code audit alone.

---

## 37. UI / device robustness

- `UIDesignRequiresCompatibility` for tab/nav bar layout (Info.plist).
- Experience chrome / opaque headers (`ExperienceNavigationBarAppearance.swift`).
- **NEEDS MANUAL VERIFICATION:** Global upload bar vs tab bar geometry on SE + Pro Max.

---

## 38. Empty / error / offline states

- Widespread `ExperienceErrorState`, `.failed` phases in ViewModels.
- `ProEntitlementResponseSanitizer` / `toUserFacingErrorMessage` on server — **manual test** raw PostgREST errors not shown.

---

## 39. App Store review / policy

| Topic | Readiness |
|-------|-----------|
| Sign in with Apple | Implemented |
| Account deletion | In-app + API |
| IAP + restore | Implemented in code |
| UGC report | `ContentReportPresenter`, migrations `20260903230000_content_reports.sql` |
| Privacy policy / Terms | Settings legal routes |
| Trading disclaimer | **Verify** AI + marketing copy |
| Demo account | **MUST DO** for review notes |
| Broker OAuth | Read-only import narrative — OK if copy accurate |

### Suggested App Review notes (draft)

- Test account credentials (email + password) and optional Apple ID test steps.
- TraxPro: sandbox subscription product IDs.
- TradeTraxs is a **journal/social** app; **does not execute trades**.
- Broker login imports historical fills only (manual sync).
- Rithmic connect hidden in production build unless test env enabled server-side.

---

## 40. UGC safety / moderation

- Report flows for posts, trades, reels, comments, profiles, rooms (ContentReport support types).
- Block filtering on feed bootstrap RPC when migration applied.

---

## 41. Legal / trading product risk

- Position as journal + analytics + social; broker import read-only.
- **Flag for legal review:** Any marketing strings promising returns (not fully audited in this pass).

---

## 42. Production observability

- `AppLog` / OSLog categories; extensive **DEBUG-only** probes.
- No third-party crash SDK grep in this pass — **NEEDS MANUAL VERIFICATION** (Xcode Organizer / Firebase if integrated).

---

## 43. Warnings / technical debt

| Class | Examples |
|-------|----------|
| **BENIGN** | Run script “Copy Secrets.plist” every build (Xcode note) |
| **P2** | Legacy leaderboard client stub still in graph |
| **P2** | `viewerSyncState` off by default |
| **P1** | Profile `uniqueKeysWithValues` in Explore/Messages |

Compiler warnings: not enumerated in this audit — run `xcodebuild` with warning flags in CI if needed.

---

## 44. Dead / legacy code

- `DefaultLeaderboardRepository` — retired corpus (safe if RPC path used).
- Broker auto-sync worker migrations exist server-side; V1 UI is manual import — **do not expose worker language** (**verify strings**).
- Old reel caption constraint — **dropped** in DB migration.

---

## 45. Final manual TestFlight test matrix

Minimal high-value pass (check each):

1. Fresh install → sign up → complete onboarding → land in shell  
2. Existing user upgrade (if applicable) → session restore  
3. Apple login (new + returning) + Google/email  
4. Logout → login different user → **no prior data**  
5. TraxPro: purchase (sandbox), restore, foreground refresh  
6. Add trade → edit → delete → dashboard/calendar/profile update  
7. Image on trade; Reel with **caption + linked trade**; Story create/view  
8. Achievement create → profile + feed  
9. Feed: like, comment, share, report; block user → content hides  
10. Profile self/other, private account, follow request  
11. DM send/receive, media, push tap routing  
12. Trade Room: join, member list (**no crash**), owner vs member Room Info/Settings (no owner Leave; owner Delete)  
13. Channels permissions save; tags create/delete  
14. Vault save/remove; logout clears  
15. Calendar month + year same totals  
16. Tradovate: connect → map account → import → review imported  
17. Rithmic: only if test env enabled — connect smoke  
18. Offline → retry; 401 → re-auth  
19. Background upload after dismissing composer  
20. Local reminders (toggle in Settings); timezone sanity  
21. Account deletion staging test account  
22. Kill app → relaunch session  

---

## 46. App Store submission checklist (external)

| Item | Repo status |
|------|-------------|
| Bundle ID `com.tradetraxs.TradeTraxs` | **DONE** |
| Version 1.0 (9) | **DONE** |
| Privacy manifest | **DONE** |
| Sign in with Apple entitlement | **DONE** |
| Associated domains | **DONE** (must match apple-app-site-association on host) |
| Production APNs entitlement (Release) | **DONE** |
| IAP product IDs in code | **DONE** (defaults) |
| IAP products in ASC | **MUST DO** |
| Subscription group | **MUST DO** |
| Apple Server Notifications URL | **MUST DO** |
| Push cert/key in ASC + server | **NEEDS MANUAL VERIFICATION** |
| Distribution cert + profile | **MUST DO** |
| Archive secrets (Supabase) | **MUST DO** |
| Production Supabase migrations | **MUST DO** |
| BFF env (Stripe, Supabase service role, broker secrets) | **NEEDS MANUAL VERIFICATION** |
| Screenshots, description, keywords, age rating | **MUST DO** |
| Privacy nutrition labels (ASC) | **MUST DO** (align with PrivacyInfo) |
| Support URL + privacy URL | **MUST DO** |
| Demo account for review | **MUST DO** |
| Tradovate production OAuth app | **NEEDS MANUAL VERIFICATION** |
| Rithmic production approval | **Not required for v1 if UI hidden** |

---

## 47. Final release scores

| Category | Grade |
|----------|-------|
| **Overall release grade** | **B−** |
| **App Store readiness** | **74%** |
| **Architecture** | **A−** |
| **Runtime stability** | **B** (Room Members fix; residual dict risks) |
| **Security / privacy** | **B+** |
| **Performance** | **B** |
| **Social platform readiness** | **B+** |
| **Broker integration readiness** | **B** (Tradovate path; Rithmic gated) |
| **Subscription readiness** | **C+** |
| **Apple compliance readiness** | **B+** |

---

## Priority findings

### P0 — BLOCKS SUBMISSION

#### P0-1 Production database migration parity

- **Issue:** Native + BFF depend on September 202609 RPC/schema (broker execution identity, profile tab reels, feed block filter, apple subscriptions, rooms, vault, etc.). Unapplied migrations cause runtime 404/RPC errors and broken broker import.
- **Evidence:** `supabase/migrations/20260915140000_broker_execution_user_fill_identity.sql`, `20260915120000_rpc_v1_profile_tab_reels_linked_trade.sql`, + 50 sibling files; iOS broker repos call BFF that uses these tables.
- **Impact:** Production-only failures after submit; broker import broken; possible App Review failure on core flows.
- **Smallest fix:** Apply full migration chain to production Supabase; smoke-test RPCs from staging build.

#### P0-2 Release archive Supabase configuration

- **Issue:** Release `fatalError` when Supabase URL/anon key missing.
- **Evidence:** `AppConfigurationValidator.swift:36-42`; `Secrets.example.plist`.
- **Impact:** Archive runs crash on launch in TestFlight/App Store build.
- **Smallest fix:** Ensure Copy Secrets build phase populates `Secrets.plist` or `Secrets.production.plist` in CI/archive without committing secrets to git.

#### P0-3 App Store Connect IAP + server notification wiring (if shipping TraxPro on iOS)

- **Issue:** Product IDs exist in code but ASC products/group/notifications must match for purchase/restore/compliance.
- **Evidence:** `TraxProProductConfiguration.swift`; `StoreKitSubscriptionService.swift`; `/api/apple/subscription/*`.
- **Impact:** Review rejection for incomplete IAP; purchases fail in production.
- **Smallest fix:** Create products, enable server notifications, sandbox E2E test.

---

### P1 — FIX BEFORE SUBMITTING IF POSSIBLE

#### P1-1 Residual ProfileID `uniqueKeysWithValues` crashes

- **Issue:** Explore/Messages/Leaderboard can trap on duplicate profile IDs from API.
- **Evidence:** `ExploreProfileHydration.swift:114`, `MessagingBootstrap.swift:53`, `LeaderboardSessionStore.swift:98`.
- **Impact:** Rare but fatal; same signature as fixed Room Members crash.
- **Smallest fix:** Reuse `ProfileDictionaryByID.build` in these hydration paths.

#### P1-2 iOS 18.0 deployment target

- **Issue:** Excludes all iOS 17 devices.
- **Evidence:** `project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET = 18.0`.
- **Impact:** Smaller addressable market; unexpected if marketing says “iOS 17+”.
- **Smallest fix:** Product decision — lower to 17.0 only if QA passes on 17.

#### P1-3 Production migration smoke before TestFlight wide release

- **Issue:** Same as P0-1 but staged validation — run automated RPC contract tests against prod-like staging.
- **Evidence:** `BackendV2ContractTests.swift`, many RPC migrations.
- **Smallest fix:** Deploy to staging → run iOS against staging → then prod.

#### P1-4 Cross-account session isolation manual proof

- **Issue:** Large cache surface; any missed store leaks PII.
- **Evidence:** `SessionScopedCaches.swift` (extensive list).
- **Smallest fix:** Execute test matrix logout/login scenario; fix any leaked UI if found.

#### P1-5 Associated domains / universal links live

- **Issue:** Entitlements declare applinks; host must serve AASA file.
- **Evidence:** Entitlements plists.
- **Smallest fix:** Verify `https://www.tradetraxs.com/.well-known/apple-app-site-association`.

#### P1-6 Tradovate production OAuth redirect

- **Issue:** Deep link `tradetraxs://` must match Tradovate app registration for production BFF.
- **Evidence:** Info.plist URL scheme; Tradovate integration routes in `app/api/integrations/`.
- **Smallest fix:** End-to-end connect on TestFlight production build.

---

### P2 — SAFE POST-LAUNCH

- Enable `backendV2.viewerSyncState` after RPC deployed for finer cache reconciliation.
- Startup duplicate REST/RPC request reduction (RoomMembers, profile batch).
- Explore/Leaderboard scale hardening.
- Full VoiceOver / Dynamic Type audit.
- Supabase advisor index/policy cleanup.
- Production observability (crash reporting dashboard).

---

### DO NOT TOUCH BEFORE LAUNCH

- Backend V2 bootstrap architecture wholesale changes  
- GlobalUploadCoordinator redesign  
- Realtime → polling migration  
- Broker continuous auto-sync worker exposure in V1 UI  
- Broad replace-all of `Dictionary(uniqueKeysWithValues:)` app-wide  
- Trade Room UI/permission product changes beyond bugfixes  

---

## Appendix A — Verified build

```
xcodebuild -scheme TradeTraxs -configuration Release \
  -destination 'generic/platform=iOS Simulator' build
→ ** BUILD SUCCEEDED **
→ Validate /Users/.../TradeTraxs.app -validate-for-store
```

---

## Appendix B — Profile duplicate crash (closed)

| Item | Detail |
|------|--------|
| **Crash site (before fix)** | `RoomMembersViewModel` `Dictionary(uniqueKeysWithValues: (fetchedProfiles + activeRows.map(\.profile))...)` |
| **Cause** | Same `ProfileID` in embedded membership profiles and batch-fetched profiles |
| **Fix** | `ProfileDictionaryByID.build(embeddedProfiles, fetchedProfiles)` — fetched wins |
| **Adjacent** | `SessionProfileStore.merge` hardened |

---

*End of audit document.*
