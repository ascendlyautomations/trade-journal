# TradeTraxs production readiness audit

Date: 2026-10-24 (updated same day with journey, race, and persona coverage)  
Scope: repository code only (Web, native iOS, Supabase migrations, API routes, Vercel config).  
Method: read-only. No files were changed except this report. No builds, tests, migrations, or production queries were run.

Live flag values, Stripe/Apple dashboard webhook registration, Vercel plan, column grants that are not in migrations, and any policies applied outside `supabase/migrations` are marked **unverifiable**.

## 1. Overall assessment

TradeTraxs is built as a **free product with optional billing that is off unless remote flags are turned on**. Signup, onboarding, and the old checkout wall do not block a signed-in user. Trade ownership, expense/income ledgers, broker token storage, Sign in with Apple, in-app account deletion, and StoreKit-without-Stripe-links are implemented in code.

It is **not ready to turn paid enforcement on**, and it is **not safe to treat “private” Trade Rooms as hidden**. Two database behaviors can delete the wrong payout achievement or accept a Stripe charge without updating the profile. `public.accounts` has no RLS statements in this repository, so owner isolation for trading accounts cannot be proven from code.

Several journeys write one store and skip the next: web leave versus iOS join, Tradovate fills versus trades, iOS payout cycle id versus the closed cycle, and web signup `is_pro: true` versus an inactive Stripe status. Those splits are worse than isolated feature bugs because the UI can look finished.

**Verdict:** acceptable to keep operating as a free app after the private-room and accounts-RLS checks below. Not acceptable to enable TraxPro enforcement, or to describe rooms as private, until the critical items are fixed and the unverifiable production settings are confirmed. Dual-app users and anyone who records a payout on iOS are already hitting split state.

## 2. Critical blockers

### C1. Rooms marked private are readable and joinable by any signed-in user

- **Severity:** Critical
- **Platform:** Supabase, Web, iOS
- **Kind:** Confirmed defect
- **Where:** `supabase/migrations/20260606120000_rooms_enable_rls.sql` (`rooms_select_profile_public`, `rooms_select_invite`); `supabase/migrations/20261001060000_room_join_and_remove_follower_privacy.sql` (`room_members_insert_self`); `lib/tradeRoomConfiguration.ts` `effectiveJoinPolicy`; `lib/tradeRoomJoinFlow.ts` `roomRequiresJoinApproval`; `lib/joinTradeRoom.ts` `joinTradeRoom`; iOS `TradeRoomConfiguration.effectiveJoinPolicy`
- **Evidence:** `rooms_select_profile_public` allows `anon` and `authenticated` to select every room with `owner_user_id is not null`. No later migration drops that policy. `effectiveJoinPolicy` returns `"open"` whenever visibility is private, and `tradeRoomConfiguration.test.ts` asserts that. `roomRequiresJoinApproval` returns false for private rooms. `joinTradeRoom` inserts directly into `room_members`. The insert policy allows that insert when `join_policy` is `open` and the user is not banned. It does not check `is_private`.
- **Impact:** Discovery UI can hide a private room, but any client with the anon or user key can list it and, once signed in, join it and then read messages under `room_messages_select_member`. A kicked member can rejoin while the stored policy stays `open`. The approval RPC correctly rejects private rooms (`room_not_requestable` in `20260908180000_trade_room_join_requests_complete.sql`); the direct insert path does not use that RPC.
- **Fix:** Decide the product rule. If private means unlisted-but-link-joinable, still remove the blanket SELECT and require a slug or membership to read the row. If private means invite-only, stop forcing `join_policy = open`, and reject self-insert unless the user is the owner or has an approved request.

### C2. Stripe webhook acknowledges failed membership writes

- **Severity:** Critical once anyone is charged. High today, because checkout is still offered.
- **Platform:** Web
- **Kind:** Confirmed defect
- **Where:** `app/api/stripe/webhook/route.ts` `POST`, especially `checkout.session.completed` (profile update around the `upErr` log) and the final `return new Response("OK", { status: 200 })`
- **Evidence:** A failed `profiles` update is logged and does not change the HTTP status. `invoice.paid` also returns 200 when the paying profile cannot be found. Stripe will not retry a 200. Later `customer.subscription.updated` / `deleted` events look the profile up by `stripe_customer_id` only. If that id was never saved, those events cannot repair the row.
- **Impact:** A card can be billed, or a trial started, and `is_pro` / `subscription_status` stay unchanged. With enforcement off, the user already has the free product, so they paid for no extra capability and the books are wrong. With enforcement on, they paid and stayed Free.
- **Fix:** Return 500 when the membership write fails or the customer cannot be mapped, after the signature check. Persist `event.id` and ignore duplicates. On checkout completion, write `stripe_customer_id` before any other field, and look up by `metadata.user_id` when the customer id misses.

### C3. `public.accounts` owner isolation is not in the migration history

- **Severity:** Critical if production RLS is off. Unverifiable from the repo.
- **Platform:** Supabase
- **Kind:** Cannot verify from repository code
- **Where:** `supabase/migrations` alters `public.accounts` many times (`20260603120000_accounts_is_active.sql` and later) and never contains `enable row level security` or a policy `on public.accounts`. Related tables do: `account_payout_cycles`, `account_payout_entries`, `user_accounts`, `broker_integration_accounts`. `public.trades` is owner-or-public (`20260609120000_trades_secure_rls.sql`).
- **Impact:** If the live table was created without RLS, the anon key can read or write every trading account (name, size, firm, drawdown). If RLS was enabled in the dashboard or a migration that is not in this folder, this finding is void.
- **Fix:** In the Supabase SQL editor, confirm `relrowsecurity` on `public.accounts` and list policies. If RLS is off, enable it and add owner-only policies before any other work. Commit that migration so the repo matches production.

## 3. High-priority correctness and security

### H1. Cancelling a trial does not end Pro access

- **Severity:** High when enforcement is on. Medium while it is off.
- **Platform:** Web (server entitlement shared with iOS)
- **Kind:** Confirmed defect
- **Where:** `app/api/stripe/webhook/route.ts` `SUBSCRIPTION_INACTIVE` and `customer.subscription.deleted`; `lib/subscription.ts` `isProActive`; `lib/traxProEntitlement.ts` `isTraxProActive`
- **Evidence:** Deleted subscriptions set `is_pro: false` and `subscription_status: "inactive"` and do not clear `trial_end`. `isProActive` returns true for any future `trial_end` with no status check. `isTraxProActive` returns true as soon as `isProActive` does.
- **Impact:** A user who cancels during the 14-day Checkout trial keeps Pro until the original `trial_end`. That is access after the subscription row is gone.
- **Fix:** On `customer.subscription.deleted`, set `trial_end` to null, or ignore `trial_end` unless `subscription_status` is `trialing`.

### H2. No Stripe event idempotency

- **Severity:** High
- **Platform:** Web
- **Kind:** Likely risk (the missing table is confirmed; a production reordering incident was not observed)
- **Where:** `app/api/stripe/webhook/route.ts`. Contrast `lib/appleSubscriptionNotifications.ts`, which inserts `notification_uuid` and treats Postgres `23505` as a duplicate, and `lib/appleSubscriptionState.ts` `shouldApplyAppleSubscriptionUpdate`, which drops older `signedDate` values.
- **Evidence:** Profile updates are last write wins. Nothing stores `event.id` or compares `event.created`. A delayed `customer.subscription.updated` whose object is still `active` can set `is_pro` true after `customer.subscription.deleted`.
- **Impact:** Entitlement can flip back to Pro after a cancellation, or stay stale after an out-of-order renewal.
- **Fix:** Unique `stripe_events.id`. Apply subscription changes only when the event is newer than the stored subscription version.

### H3. Checkout is offered while the paywall flag is off

- **Severity:** High for billing integrity
- **Platform:** Web
- **Kind:** Confirmed
- **Where:** `app/api/create-checkout-session/route.ts`; `app/settings/page.tsx` (Free users call `startTraxProCheckout`); `lib/proMonetizationPolicy.ts` `canPresentProPaywall`
- **Evidence:** The shared upgrade sheet requires `entitlementEnforcementEnabled` and `webPaywallEnabled`. Settings and Pricing do not. `CHECKOUT_TRIAL_ENABLED` still adds a trial. SQL free-plan triggers return immediately when `free_plan_limits_enforced()` is false (`20261007230000_free_plan_total_accounts_and_trade_slots.sql`). `app_monetization_settings` defaults `ios_paywall_enabled` and `entitlement_enforcement_enabled` to false (`20260929150000_monetization_runtime_config.sql`). Missing config is treated as false in `lib/monetizationConfig.ts`.
- **Impact:** A Free user can be sent to Stripe and charged for access the free account already has. The in-app sheet correctly stays hidden.
- **Fix:** Until enforcement is on, remove or disable Settings and Pricing checkout. When it is on, keep one gate in `create-checkout-session`.

### H4. Stripe subscribers are labeled `manual`

- **Severity:** High for support and cancellation copy. Access math still works.
- **Platform:** Web and iOS
- **Kind:** Confirmed defect
- **Where:** `lib/traxProEntitlement.ts` `resolveTraxProEntitlementSource`
- **Evidence:** The function returns `"manual"` as soon as `is_pro === true`, before it looks at `subscription_status`. The webhook sets `is_pro: true` for every `active` or `trialing` subscription. Web Settings repairs the portal button (`resolveBillingProvider` in `lib/billingEntitlement.ts` treats `manual` plus a live Stripe status as Stripe). iOS deletion copy that looks for source `stripe` does not.
- **Impact:** A normal Stripe subscriber looks like a manual grant. iOS may not tell them billing is outside the App Store. Server delete still tries to cancel Stripe.
- **Fix:** Resolve `stripe` before `manual`. Reserve `manual` for `is_pro` with no Stripe, Apple, creator, or early-access grant.

### H5. Deleting one payout can delete a different achievement

- **Severity:** High for that user’s social history. Not cross-user.
- **Platform:** Supabase, Web, iOS (shared RPC)
- **Kind:** Confirmed defect
- **Where:** `supabase/migrations/20261024043000_delete_prop_payout_restore_balance.sql` `delete_prop_payout`; callers `lib/propfirmPayoutCycles.ts` and iOS `DefaultTradeRepository`
- **Evidence:** The function requires `auth.uid()` and `account_payout_cycles.user_id = auth.uid()`. The achievement delete also matches `account_id` plus amount within `$0.02` plus `achieved_at` within three days of the cycle end, even when `metadata.account_payout_cycle_id` does not match. `achievement_posts.achievement_id` cascades.
- **Impact:** Two payouts of the same amount on one account, a few days apart, can lose the wrong achievement and its post.
- **Fix:** Delete only the row whose metadata cycle id matches, or the row this payout created. Drop the amount-and-date fallback.

### H6. Moderators can lift any ban

- **Severity:** High inside a room that uses moderators
- **Platform:** Supabase
- **Kind:** Confirmed defect
- **Where:** `supabase/migrations/20261024163000_trade_room_moderator_permissions.sql` `room_bans_delete_moderator`
- **Evidence:** Delete is allowed when `can_moderate_trade_room(room_id, auth.uid())` is true. It does not check who was banned. Insert still uses `can_moderate_room_member_target`, which blocks bans of the owner and of members who already have a Moderator or Admin tag. Tag insert refuses Moderator and Admin unless `can_manage_trade_room` (owner, or a platform admin on an official room). A member cannot grant themselves moderator.
- **Impact:** A moderator can remove a ban the owner placed, including a ban on another moderator, then that person can rejoin because private/open rooms allow self-insert (C1). They still cannot delete the owner’s messages (`room_messages_delete_moderator` excludes the owner).
- **Fix:** Allow ban delete only for bans the actor created, or only for targets they would be allowed to ban.

## 4. Medium-priority performance and consistency

### M1. Dashboard REST bootstrap stops at 500 trades

- **Severity:** Medium
- **Platform:** Web
- **Kind:** Confirmed limitation
- **Where:** `lib/backendV2/dashboardBootstrapRepository.ts` `DASHBOARD_TRADE_LIMIT = 500`. The session cache first page is `INITIAL_TRADES_LIMIT = 120` in `lib/appDataCache.ts`.
- **Evidence:** The REST dashboard provider loads a fixed window. Journals larger than 500 trades are not fully represented on that path. The V3 RPC path is separate and should stay as it is.
- **Impact:** At a few hundred trades, totals on the REST fallback can disagree with the full journal. This shows up well before 10,000 users; it shows up per user who journals heavily.
- **Fix:** Keep V3. Make the REST fallback page until the filtered set is complete, or label the window. Do not reload the full table on every dashboard visit.

### M2. CSV import has no uniqueness guard

- **Severity:** Medium
- **Platform:** Web and iOS
- **Kind:** Confirmed
- **Where:** `supabase/migrations/20260902210000_trade_import_fingerprints.sql` (index, not unique); iOS `CSVTradeBuilder.swift` (no match against existing journal rows)
- **Evidence:** Broker fills are unique on `(user_id, provider, external_fill_id)` (`20260915140000_broker_execution_user_fill_identity.sql`) and trades are unique on `(user_id, broker_lifecycle_id)`. CSV fingerprints are only indexed.
- **Impact:** Importing the same file twice inserts a second copy of every trade and doubles P&L.
- **Fix:** Unique `(user_id, import_fingerprint)` where the fingerprint is non-null, and skip conflicts in the importer.

### M3. Tradovate history is the current API window, not an archive

- **Severity:** Medium
- **Platform:** Web (iOS uses the same routes)
- **Kind:** Confirmed
- **Where:** `lib/integrations/tradovate/tradovateHistoricalAcquisitionCore.ts`
- **Evidence:** `order/list` and `fill/list` are documented as the current visibility window. An empty HTTP 200 is treated as no API-visible history. Rithmic uses `requestShowFillHistory` with an `ssboe` checkpoint; overlap is absorbed by the fill unique index.
- **Impact:** Older Tradovate fills never appear. Users can think the journal is complete.
- **Fix:** Surface “synced through &lt;date&gt;” in the connection UI. Do not present an empty 200 as a finished backfill.

### M4. Web payout amounts use binary floating point

- **Severity:** Medium
- **Platform:** Web versus iOS
- **Kind:** Confirmed
- **Where:** `parseWithdrawalAmount` in `lib/accountPayoutEntry.ts`; `mapPayoutCycleRow` in `lib/propfirmPayoutCycles.ts`. Expenses use integer cents (`parseMoneyToCents`) and `numeric(14,2)`. iOS payout and expense models use `Decimal`.
- **Impact:** Large web payout sums can drift by a cent from iOS and from the expense ledger. Expenses and income do not write `trades.pnl` or account balances. Payout cycles do change prop-firm balance on purpose.
- **Fix:** Store and sum payout cents as integers or `numeric`, matching expenses.

### M5. Expense category save cannot update

- **Severity:** Medium for the expense UI, low for security
- **Platform:** Supabase, Web, iOS
- **Kind:** Confirmed
- **Where:** `supabase/migrations/20261024033135_expense_tracker_kinds.sql` grants `authenticated` select, insert, and delete on `expense_categories` and creates no update policy. `lib/propFirmExpenses.ts` `saveExpenseCategory` and iOS `PropFirmExpenseRepository.saveCategory` upsert on `(user_id, name)`.
- **Impact:** The first save works. Saving the same category again fails. No cross-user access.
- **Fix:** Add an owner update policy and grant `update`, or make the client insert-if-absent.

### M6. Account purchase expense does not follow renames

- **Severity:** Medium
- **Platform:** Web and iOS (shared RPC)
- **Kind:** Confirmed
- **Where:** `upsert_prop_firm_account_purchase_expense`
- **Evidence:** Partial unique index `prop_firm_expenses_account_purchase_uidx` keeps one `account_purchase` row per account. The conflict update changes `cost_per_account` and `date_paid` only. A zero cost does not delete the existing row.
- **Impact:** Renaming the account or switching eval/funded leaves the old label on the expense. Creating the account does not insert a second purchase row. A failed broker link deletes the new account’s expenses and then the account row.
- **Fix:** On account update, patch firm name and expense type on the linked `account_purchase` row. Delete the row when cost becomes 0 if that is the product rule.

### M7. Apple’s first subscription grant depends on the device

- **Severity:** Medium when the iOS paywall is on. Inert while the flag is false.
- **Platform:** iOS and Web API
- **Kind:** Confirmed
- **Where:** `lib/appleSubscriptionNotifications.ts` (returns 200 and `applied: false` when no `apple_subscriptions` row exists); device sync `POST /api/apple/subscription/sync`
- **Impact:** Apple can charge, the server can stay Free, and the purchase UI stays on “verification pending” until a successful sync. Later notifications do not create the row.
- **Fix:** Create the row from the verified notification when `appAccountToken` or the original transaction maps to a user. Return 500 when the map fails so Apple retries.

### M8. Monthly IAP product id does not match the other plans

- **Severity:** Medium when the iOS paywall is on
- **Platform:** iOS
- **Kind:** Confirmed inconsistency. Whether App Store Connect matches either id is unverifiable.
- **Where:** `native-ios/.../Domain/Models/Billing/TraxProProductConfiguration.swift`
- **Evidence:** Catalog id is `com.tradetraxs.traxspro.monthly`. Six-month and yearly are `com.tradetraxs.traxpro.sixmonth` and `com.tradetraxs.traxpro.yearly` (`traxpro`, no s). `com.tradetraxs.traxpro.monthly` is accepted only when mapping an already-owned product.
- **Impact:** If the live monthly product is `traxpro.monthly`, StoreKit returns no monthly product.
- **Fix:** One spelling, used for load and for restore. Confirm the three ids in App Store Connect before enabling `ios_paywall_enabled`.

### M9. Release builds crash if Supabase client config is missing

- **Severity:** Medium for the release process
- **Platform:** iOS
- **Kind:** Confirmed
- **Where:** `native-ios/.../Config/AppConfigurationValidator.swift` `assertReadyForLaunch`
- **Evidence:** Production configuration calls `fatalError` when Supabase is not configured. Whether the archive machine injects `Secrets.plist` is unverifiable.
- **Impact:** A Release build without secrets will not stay open. A correctly signed archive is unaffected.
- **Fix:** Keep the check. Fail CI before archive if the secrets file is absent, so TestFlight never gets that binary.

### M10. Three Vercel crons; Hobby allows two

- **Severity:** Medium operational
- **Platform:** Web deployment
- **Kind:** Likely risk. The project’s Vercel plan is unverifiable.
- **Where:** `vercel.json`
- **Evidence:** `/api/cron/apple-sign-in-revoke` daily 06:00 UTC, `/api/cron/expired-stories` daily 07:15 UTC, `/api/cron/weekly-trading-reports` Saturday 17:00 UTC. Each route returns 401 unless `Authorization` is `Bearer ${CRON_SECRET}`. A missing secret also returns 401. None run more often than daily.
- **Impact:** On Hobby, one of the three jobs may never register. Apple token revocation, story expiry, or the weekly report push would silently stop.
- **Fix:** Confirm the project is on Pro, or collapse two jobs into one scheduled route.

### M11. Duplicate profile ids can trap Explore or Leaderboard

- **Severity:** Medium
- **Platform:** iOS
- **Kind:** Confirmed crash class, only if the API returns a repeated id
- **Where:** `ExploreViewModel`, `ExploreProfileHydration`, `SuggestedTradersViewModel`, `LeaderboardSessionStore.appendEntries` (`Dictionary(uniqueKeysWithValues:)`)
- **Evidence:** Room Members already uses `ProfileDictionaryByID` to survive duplicates. These screens do not.
- **Impact:** One duplicated profile row crashes that screen.
- **Fix:** Use the same duplicate-tolerant dictionary.

### M12. Past-due Stripe drops Pro immediately; Apple billing retry does not

- **Severity:** Medium when enforcement is on
- **Platform:** Web versus iOS
- **Kind:** Confirmed behavior
- **Where:** `buildSubscriptionProfileUpdatePayload` (`is_pro` only for `active` or `trialing`); `isAppleSubscriptionActive` in `lib/appleSubscription.ts` (grace and billing-retry stay active)
- **Impact:** A failed card renewal removes web Pro the same day. An Apple billing retry keeps access. Users on the two stores are treated differently.
- **Fix:** Pick one grace rule and apply it to both.

## 5. Low-priority improvements

### L1. Creator redeem trusts `p_user_id` inside the function

- **Severity:** Low
- **Kind:** Likely risk only if execute is later granted to `authenticated`
- **Where:** `supabase/migrations/20260714010000_creator_redeem_exhausted_vs_invalid.sql` `redeem_creator_access_code`
- **Evidence:** `GRANT EXECUTE` is `service_role` only. The route `app/api/creator/redeem/route.ts` passes the session user id. The function no longer checks `rate_limit_is_service_role()` or `auth.uid()`.
- **Fix:** Reject when `p_user_id` is not `auth.uid()` unless the caller is service role.

### L2. Anonymous push unregister

- **Severity:** Low
- **Kind:** Confirmed
- **Where:** `POST /api/push/unregister`
- **Evidence:** A signed-out caller can delete a `device_push_tokens` row by token value when the token is at least 16 characters. Register and `allDevices` still require a session.
- **Impact:** Someone who already has a device token can unsubscribe it. They cannot enumerate tokens.
- **Fix:** Require the session user id to match the token row, and keep a short signed-out path only for the token this install just used.

### L3. Account deletion continues if Stripe or Apple revoke fails

- **Severity:** Low
- **Kind:** Confirmed
- **Where:** `lib/deleteUserAdmin.ts` `cancelStripeSubscriptions`; Apple revoke queue drained by `/api/cron/apple-sign-in-revoke`
- **Impact:** The TradeTraxs user is removed. A Stripe subscription can keep billing. Apple revocation waits for the daily cron, or is skipped if Apple OAuth env is missing.
- **Fix:** Block self-serve delete until Stripe cancel succeeds, or show a billing warning and retry. Alert when the revoke queue is non-empty after the cron.

### L4. Checkout trial is offered again if the Stripe list call throws

- **Severity:** Low
- **Kind:** Likely risk
- **Where:** `app/api/create-checkout-session/route.ts` `resolveCheckoutTrialPeriodDays`
- **Evidence:** A profile that already has `trial_end` is not offered another trial. If the profile has no `trial_end` and the Stripe subscription list throws, the trial is still attached.
- **Fix:** Fail the checkout request when trial history cannot be read.

### L5. Subscription retrieve failure fail-opens to Pro

- **Severity:** Low
- **Kind:** Confirmed on that failure path
- **Where:** `checkout.session.completed` fallback `SUBSCRIPTION_ACTIVE` when `subscriptions.retrieve` throws
- **Impact:** A Checkout session that cannot be read still sets `is_pro: true`.
- **Fix:** Return 500 and let Stripe retry. Do not write `is_pro` until the subscription object is in hand.

### L6. Stale comment that GRDB is not linked

- **Severity:** Low
- **Kind:** Confirmed comment drift
- **Where:** `SessionDiskCache.swift` versus `AnalyticsLocalStore` (`import GRDB`)
- **Evidence:** Logout clears in-memory stores and several disk caches. GRDB analytics rows are removed by `viewer_id` in `clearViewer`, which logout does not call. Loaders that were inspected pass `viewerID`. A full query audit was not done.
- **Fix:** Call `clearViewer` on logout, or document why rows are retained and prove every read filters `viewer_id`.

## 6. Stripe and subscription verdict

**Not ready to charge.**

What is in place:

- Checkout session requires a signed-in user (`app/api/create-checkout-session/route.ts`).
- Webhook signature is checked with `STRIPE_WEBHOOK_SECRET`.
- Monthly, six-month, and yearly are one Pro entitlement. `customer.subscription.updated` writes status, cancel-at-period-end, price id, and billing interval.
- Cancel from the app sets `cancel_at_period_end` (`app/api/stripe/cancel-subscription/route.ts`). Access continues while Stripe status stays `active` or `trialing`.
- Customer Portal session exists (`app/api/create-portal-session/route.ts`).
- Affiliate `invoice.paid` dedupes on `referrals.stripe_invoice_id`.
- Apple notifications dedupe on `notification_uuid`.
- iOS does not open Stripe Checkout or the Portal. Purchases are StoreKit and return immediately when `iosPaywallEnabled` is false.

What is not safe:

- Failed profile writes return HTTP 200 (C2).
- No Stripe event id (H2).
- Future `trial_end` keeps Pro after deletion (H1).
- Checkout ignores the paywall flag (H3).
- Active Stripe subscribers are labeled `manual` (H4).
- `past_due` removes Pro with no grace (M12).
- Whether production webhooks are registered is unverifiable.

**Charged without access:** yes, if the profile update fails (C2) or the first Apple sync fails (M7).  
**Access without payment:** yes, for creator codes, early access, manual `is_pro`, and a leftover `trial_end` (H1). Those first three are intentional. The trial leftover is not.

## 7. Free-tier and access-code verdict

**Free use is ready. Paid limits are correctly off. Codes are ready for server-side redemption.**

- Completed onboarding exempts the user from the checkout wall. `needsSubscriptionCheckout` in `lib/subscriptionAccess.ts` cannot redirect a user who has finished onboarding, because that same flag makes them exempt. `/finish-trial` sends a signed-in user with a profile to the dashboard or onboarding. The legacy wall does not block free users.
- Free-plan account and trade-slot triggers no-op unless `free_plan_limits_enforced()` is true. Missing monetization config is false.
- `ProGate` blocks only when enforcement is on and access is confirmed Free.
- `redeem_creator_access_code` is service-role only, locks the code row, returns `invalid` when inactive or expired, returns `already` for the same user without burning another seat, and returns `exhausted` past `max_redemptions`. Unique `(code, user_id)`. Profiles cannot self-set `creator_access` or `is_pro`.
- Live values of the three flags are unverifiable. If production has flipped them, the free-tier verdict changes and H1–H4 become user-facing immediately.

## 8. Web readiness verdict

**Usable for the free product. Not ready to sell TraxPro from the website.**

Sound:

- Trade RLS is owner read/write plus `is_public` for everyone else.
- Expense, income, and payout-assignment tables used by `lib/propFirmExpenses.ts`, `lib/trackerIncome.ts`, and `lib/propFirmPayoutAssignments.ts` are scoped to `auth.uid()`.
- Broker link routes resolve the session user and then the connection row for that user.
- Admin user delete requires an `admin_users` row and a `DELETE` confirmation.
- `POST /api/trading-reports/notify` is hard-disabled; the weekly cron is the sender.
- No `service_role` or `sk_live` key is referenced from client bundles. `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` is the publishable key.

Not sound: C1, C2, H1–H6, M1, M2, M4, M5.

## 9. Native iOS and App Store verdict

**Can ship as a free app with the current flag defaults. Do not enable the iOS paywall until M7 and M8 are fixed and the products exist in App Store Connect.**

Confirmed in the binary:

- Sign in with Apple is on the login screen next to email/password and Google, with a SHA-256 nonce. Google is offered, so Apple is required, and it is present. A successful device sign-in was not run.
- Settings → Account → Delete Account calls `POST /api/delete-account` for the signed-in user and attempts Apple token revocation.
- Camera, microphone, and photo-library purpose strings are in `Info.plist`. `UIBackgroundModes` includes `remote-notification`. Release entitlements use `aps-environment` production. The sender uses `api.push.apple.com` only when `APNS_PRODUCTION=true`; otherwise sandbox. A production token sent to sandbox will not arrive. Key material on Vercel is unverifiable.
- No Stripe checkout URL in the native purchase UI. With the paywall flag off, copy says features are included at no extra cost, so review may never see a paywall. That matches a free app. If the flag is on, digital access must stay on StoreKit. The code does that.
- `PrivacyInfo.xcprivacy` declares email, name, user ID, device ID, photos, video, audio, other user content, and other financial info, plus UserDefaults `CA92.1`. It does not declare purchase history. Billing state stores Apple product id and expiry. **Likely** App Privacy mismatch, not a proven rejection.
- Deep links for signed-out users are held in memory until the next successful sign-in (`DeepLinkRouter`). Logout clears that stash. It is not on disk.
- Deployment target iOS 18, marketing version 1.0, bundle id `com.tradetraxs.TradeTraxs`.

Release blockers if you turn billing on: M7, M8, and App Store Connect product setup. Release blocker for a bad archive: M9. Crash if discover/leaderboard payloads repeat a profile id: M11.

## 10. Supabase scalability

**Fine at 100 users. Needs attention before a few thousand heavy journals, and the private-room policy will not get safer with scale.**

What is in good shape:

- `trades` has `user_id` indexes. `room_messages` has `(room_id, created_at desc, id desc)`.
- Broker fill identity and lifecycle keys stop duplicate broker trades. A concurrent unique-index miss can leave `canonical_trade_id` unset; that is a missed link, not a second trade.
- Tradovate tokens are AES-256-GCM ciphertext. Status RPCs do not return the ciphertext. `broker_integration_connections` has RLS and no policies in migrations, so the default is deny. Rithmic passwords are not stored; sync without a password returns `rithmic_password_required`. Disconnect nulls ciphertext and marks mappings inactive. It does not delete trades.
- Expense and income rows do not write trade P&L. Tax CSV on both platforms says it does not determine tax liability, uses a calendar year or an inclusive custom range, and omits future occurrences. Tracker income is not a column in that CSV.
- Heart reactions in `20261024150000_message_reaction_heart.sql` match web and iOS clients.
- Sampled storage inserts require the object folder to be `auth.uid()`.

What will hurt:

- C1 is an authorization bug, not a load bug. It is worse as more private rooms exist.
- M1: dashboards past 500 trades on the REST path.
- M2: CSV re-imports at any scale.
- Realtime: feed, rooms, and profile each open channels per signed-in user. That is normal at 100. At 1,000 concurrent room members, fan-out on `room_messages` is the first Realtime cost. No extra unused channel was proven in this pass.
- `public.accounts` without a proven RLS policy (C3) is a data exposure, not a query-plan issue.

Deleting a TradeTraxs user (`deleteUserAdmin`) deletes trades, payout cycles, achievements, and accounts. There is no separate “delete this trading account” action. `prop_firm_expenses.account_id` is `ON DELETE SET NULL`, so an account-row delete would keep the expense. User delete cascades expenses and income through `user_id`.

## 11. Broker, finance, and social notes that are not defects

- Only Tradovate (OAuth, server token refresh, then `reconnect_required`) and Rithmic (password per request) are implemented. iOS calls the web routes and does not store broker tokens.
- Recording a payout updates `account_payout_cycles` on purpose. `delete_prop_payout` adds the amount back onto the open cycle. Historical trades stay. The extra achievement match is H5.
- Moderator self-promotion is blocked. Message delete by a moderator does not include the room owner’s messages.
- Profile, follow, like, comment, and vault paths were not re-tested at runtime. Owner RLS on trades and the sampled storage policies are the evidence for those surfaces. A full N+1 trace of every profile tab was not repeated; web wall pages are 12 rows and iOS profile tabs page separately.

## 12. Recommended order

1. Confirm `public.accounts` RLS in production. If it is off, ship an owner-only policy the same day (C3).
2. Stop private-room enumeration and open join, or change the product copy so “private” means unlisted and accept link-join only after SELECT no longer lists every room (C1).
3. Make the Stripe webhook fail closed and idempotent before any pricing button stays up (C2, H2). Hide Settings/Pricing checkout while enforcement is off (H3).
4. Clear `trial_end` on subscription delete, and classify Stripe grants as `stripe` instead of `manual` (H1, H4).
5. Narrow `delete_prop_payout` achievement delete and `room_bans_delete_moderator` (H5, H6).
6. Unique CSV fingerprints, expense-category update policy, integer payout cents (M2, M5, M4).
7. Before `ios_paywall_enabled`: align IAP ids, create the Apple subscription row from the server notification, and confirm App Store Connect (M7, M8).
8. Confirm Vercel is on a plan that runs three crons, and that `APNS_PRODUCTION`, `CRON_SECRET`, Stripe webhook endpoint, and Apple notification endpoint are set (M10, push).
9. REST dashboard window and Explore duplicate-id crash (M1, M11) after the security items.
10. After the security items: web leave / iOS join (J1), Tradovate trade-write swallow (J2), web signup `is_pro` (J3), iOS payout cycle id (J4), first-payout `cycle_number` (J5).

## 13. User journeys and split state

These are cases where one step commits and the next does not. Ranked by how often a real user hits them and how bad the leftover is, not by theoretical severity.

### J1. Leave on web, then join on iOS, fails

- **User impact:** High for anyone who uses both apps. Leave is a normal action. The next iOS join then fails until they rejoin on web.
- **Platform:** Web + iOS + `room_members`
- **Kind:** Confirmed defect
- **Where:** `app/community/page.tsx` `handleLeaveRoom`; `lib/joinTradeRoom.ts`; iOS `DefaultRoomRepository.join` / `leave`; PK in `supabase/migrations/20260422140000_room_members_and_room_image.sql`
- **Journey:** Member leaves a room on web → later taps Join on iOS.
- **Succeeds:** Web sets `left_at`. The `(room_id, user_id)` row stays. The sidebar updates before the write and rolls back only if that update errors.
- **Fails:** iOS `join` always inserts. Postgres rejects the duplicate key. iOS shows an error and stays left. Insert RLS also requires `left_at is null` on a new row (`20261001060000_room_join_and_remove_follower_privacy.sql`), so even a unique-key bypass would not reactivate.
- **Leftover:** Soft-left membership. Web rejoin clears `left_at`. iOS cannot.
- **Fix:** iOS join must update `left_at` to null when a row already exists, matching `joinTradeRoom`. Prefer one RPC for join and leave.

### J2. Tradovate sync reports success when trade writes fail

- **User impact:** High for connected Tradovate accounts. The connection UI looks finished. The journal is missing those trades.
- **Platform:** Web sync (iOS reads the same `trades` later)
- **Kind:** Confirmed defect
- **Where:** `lib/integrations/tradovate/syncTradovateBrokerAccount.ts` (fills insert, then success release); `lib/integrations/tradovate/persistBrokerTrades.ts` (failed update not counted; failed insert `continue`; execution-link update result ignored)
- **Journey:** Connect Tradovate → account mapped → fill sync.
- **Succeeds:** Each fill is stored in `broker_integration_executions`. Duplicate fills are ignored. The lock releases as success and `maxExternalFillId` moves forward.
- **Fails:** A failed trade update or insert does not fail the sync.
- **Leftover:** Fills with no trade, or a trade whose fills never get `canonical_trade_id`. The next sync retries from the ledger and can report success again. Open fills that are not a completed round-trip are intentional and are not this bug.
- **Fix:** Fail or retry the sync when any reconstructed trade write fails. Do not advance the checkpoint until `canonical_trade_id` is set.

### J3. Web signup still inserts `is_pro: true`

- **User impact:** High for every first-time web signup. iOS-first users do not get this. Combined with J8, a later Stripe checkout can look paid when it is not.
- **Platform:** Web. iOS insert path is different.
- **Kind:** Confirmed in code. Whether the live `is_pro` column accepts the insert is unverifiable (column grants are not in this folder).
- **Where:** `lib/ensureProfileForUser.ts` insert (`is_pro: true`, `subscription_status: "inactive"`); `supabase/migrations/20261007200000_profiles_signup_no_automatic_is_pro.sql` (drops the auto-grant trigger and sets the column default to false; comment says explicit insert is unchanged); `profiles_protect_privileged_fields_trigger` is `BEFORE UPDATE` only (`20260623190000_profiles_protect_privileged_fields.sql`)
- **Journey:** Create auth user → `ensureProfileForUser` inserts the profile → onboarding → dashboard.
- **Succeeds:** Auth user exists. If the insert is accepted, the row is Pro with inactive Stripe.
- **Fails:** The 2026-10-07 pause does not stop this write. Clients cannot later clear `is_pro` (update trigger).
- **Leftover:** Web-first users are labeled TraxPro before any payment. iOS-first users get `username: user_<8 hex>`, `name: "New User"`, and the false default. The first app to insert wins.
- **Fix:** Stop sending `is_pro` on insert. If a live grant already allowed it, backfill those rows to false unless they have a real Stripe, Apple, creator, or early-access grant.

### J4. iOS records the new open cycle as the completed payout

- **User impact:** Medium-high for every iOS “record payout, then share.” This is the client write that feeds H5.
- **Platform:** iOS write, Postgres, web history read
- **Kind:** Confirmed defect
- **Where:** `record_account_payout` returns `v_new_cycle_id` (`20260626200000_fix_first_payout_record.sql`); iOS `DefaultTradeRepository.recordAccountPayout` and `RecordPayoutFlowViewModel` store that uuid as the completed cycle; `WithdrawalAchievementLinkage` writes `metadata.account_payout_cycle_id`. Web share writes `{ source: "prop_firm_mode" }` only (`lib/propfirmMilestones.ts`).
- **Journey:** Record payout on iOS → RPC closes the old cycle and opens a new one → achievement / social post uses the returned id.
- **Succeeds:** Close + new open cycle commit in one transaction.
- **Fails:** The returned id is the **new open** cycle (`ended_at` null, `payout_amount` null), not the closed one.
- **Leftover:** History and the social post point at the open cycle. The next payout closes that row, so payout 1’s achievement becomes linked to payout 2. Web history only drops the achievement when the metadata id is in the completed-cycle set, or when amount, account, and date fall inside 14 days (`lib/payoutHistory.ts`).
- **Fix:** Return the closed cycle id from the RPC, or have iOS keep the open-cycle id it sent in.

### J5. First payout creates two cycles numbered 1

- **User impact:** Medium. Every first payout on an account that had no open cycle.
- **Platform:** Supabase (both clients)
- **Kind:** Confirmed
- **Where:** `20260626200000_fix_first_payout_record.sql` uses `max(cycle_number)+1` for both the closed insert and the new open insert. Unique index exists only for one **open** cycle (`20260626180000_account_payout_cycles.sql`).
- **Journey:** First payout on a new funded account.
- **Leftover:** Closed row and open row are both `cycle_number` 1. The second payout closes the open row (still 1) and opens 2, so two completed payouts display as cycle 1.
- **Fix:** Number the closed row `n` and the new open row `n+1`. Add a unique `(account_id, cycle_number)` if the product requires it.

### J6. Web share-payout can leave an achievement with no cycle

- **User impact:** Medium. Hits the “share payout” path when `record_account_payout` fails.
- **Platform:** Web
- **Kind:** Confirmed
- **Where:** `app/components/AchievementUploadModal.tsx` (insert achievement, then record payout, then delete the achievement on payout error; delete failure is only logged)
- **Journey:** Upload image → insert achievement → record cycle.
- **Succeeds:** Achievement row (and storage object) exist.
- **Fails:** Cycle RPC fails. Rollback delete can also fail.
- **Leftover:** Public achievement and image, no balance change. Firm assignment is a later upsert and is not rolled back. iOS is the opposite order: cycle first (`RecordPayoutFlowViewModel.recordPayout`), achievement later (`GlobalUploadCoordinator`). A failed achievement job does not undo the cycle. Retry skips a second insert when `savedAchievementID` is set.
- **Fix:** One RPC that writes cycle and achievement, or record the cycle first on web and attach the achievement id after.

### J7. Onboarding can report done when no profile row was updated

- **User impact:** Medium, only when auth exists and the profile insert failed or raced.
- **Platform:** Web. iOS is stricter.
- **Kind:** Confirmed
- **Where:** `app/components/ProfileOnboarding.tsx` `update().eq("id")` with no `select`; `app/onboarding/page.tsx` merges `onboarding_completed: true` into local state
- **Journey:** Signup → onboarding form → dashboard.
- **Succeeds:** PostgREST returns no error when zero rows match. The page routes to the dashboard.
- **Fails:** No profile row, or the row never gets the flag or avatar.
- **Leftover:** Auth user without a completed profile. Local UI says onboarding is done until the next fetch. Avatar can already be in storage.
- **iOS contrast:** Updates, then `selectOne`, then marks the gate complete. Deletes the new avatar object if the profile update throws.
- **Fix:** `.select("id").single()` and fail if no row. Do not set local `onboarding_completed` until that returns.

### J8. Checkout success UI from a pre-existing `is_pro`

- **User impact:** High if J3 is live. Silent: Settings plays the subscribed haptic without a new Stripe write.
- **Platform:** Web
- **Kind:** Confirmed client path. How often `is_pro` is already true in production is unverifiable, but the web insert sends it.
- **Where:** `lib/syncMembershipAfterStripeCheckout.ts` returns `reconciled: true` on the first poll if `isProActive` is true; `lib/subscription.ts` treats `is_pro === true` as Pro before Stripe status; `app/components/monetization/ProUpgradeProvider.tsx` treats that as entitlement confirmed
- **Journey:** Free (or web-signup “Pro”) user → Stripe Checkout → return to the app → poll.
- **Succeeds:** UI closes the paywall and logs `entitlement_confirmed`.
- **Fails:** Nothing checks that `subscription_status` or `trial_end` changed on this checkout.
- **Leftover:** Profile can still be `subscription_status: "inactive"` while the UI says the checkout reconciled. If `is_pro` is actually false, the poll returns `reconciled: false` and does not take this path.
- **Fix:** Require a Stripe status of `active` or `trialing`, or a `stripe_customer_id` that appeared after checkout, before celebrating.

### J9. Web trade RPC errors look like an empty or stale journal

- **User impact:** Medium when `rpc_v1_trades_owner_rows` errors. Looks like data loss. The rows are still on the server.
- **Platform:** Web. iOS throws.
- **Kind:** Confirmed
- **Where:** `lib/appDataCache.ts` `ensureFullTradesHistory` / `ensureAnalyticsTradesHistory` return cache or `[]` on RPC error; stale window `DEFAULT_STALE_MS` is five minutes. A completed history cache is reused without a refetch.
- **Journey:** Open dashboard / trades / analytics after a transient RPC failure.
- **Leftover:** Old trades for up to five minutes, or no trades. iOS also drops rows that fail mapping (`mapTradesSkippingFailures`), including missing dates (`TradeMapper.swift`). Those rows still render on web.
- **Fix:** Surface the error and keep the last good cache labeled stale. Do not replace it with `[]`.

### J10. iOS ban can remove the member and drop the ban

- **User impact:** Medium-low. Owners and moderators, when the ban insert fails.
- **Platform:** iOS
- **Kind:** Confirmed
- **Where:** `DefaultRoomRepository.banMember` uses `try?` on the `room_bans` insert, then `removeMember`
- **Journey:** Ban a member.
- **Succeeds:** `left_at` is set.
- **Fails:** Ban insert is ignored.
- **Leftover:** Person is out and not banned, so they can join again (and on web they can, because leave is soft — J1). If the ban insert works and `removeMember` throws, they stay an active member and can keep posting; new inserts are blocked by `is_room_banned`.
- **Fix:** Insert the ban first, require it to succeed, then remove. Do not swallow the insert.

## 14. Personas

| Persona | What the code does | What can go wrong |
|---|---|---|
| First-time web | Auth user, then `ensureProfileForUser` with `is_pro: true`, then onboarding | J3, J7. If the insert is accepted they are already “Pro.” |
| First-time iOS | Profile shell with generated username, `is_pro` omitted (default false), onboarding requires a returned row | Safer than web. Username is public before they finish the form. |
| Returning, either app | Session caches and (iOS) GRDB | Web trade edit is picked up on the next iOS dashboard open if `user_analytics_state.revision` bumps. A failed reconcile keeps the old GRDB screen. **Likely** bounded staleness, not a stuck split, unless that trigger does not run (unverifiable live). |
| Free user, flags default off | `entitlementEnforcementEnabled` and `free_plan_limits_enforced()` are false. `proFeatureUnlocked` / `appliesFreeTierUsageCaps` follow that. Daily trade/post limit triggers are dropped. Completed onboarding is subscription-exempt. | No second finish-trial wall. They can still open Stripe from Settings (H3) and hit J8. |
| Pro via Stripe | Webhook sets `is_pro` and status. `isProActive` is true. Source is labeled `manual` (H4). | Cancel during trial keeps Pro until `trial_end` (H1). `past_due` drops Pro immediately (M12). |
| Expired trial | `customer.subscription.deleted` sets inactive and leaves `trial_end` | They stay Pro until that timestamp (H1). |
| Promotional / creator | Service-role redeem, unique `(code, user_id)`, expired codes invalid | Looks correct. Function trusts `p_user_id` if execute is later granted to `authenticated` (L1). |
| Dual-app | Same Supabase user | J1 (rooms), J3 (which insert won), J4 (payout metadata), J9 (web cache vs iOS throw). |

## 15. Silent UI success

Confirmed cases where the UI looks finished and the authoritative write did not:

1. Stripe webhook HTTP 200 after a failed profile update (C2) — Stripe will not retry.
2. Checkout poll “subscribed” because `is_pro` was already true (J8).
3. Tradovate sync success with fills and no trades (J2).
4. Web onboarding complete with zero profile rows updated (J7).
5. Web share-payout: user sees the thrown error if rollback delete works; if that delete also fails, a later refresh shows an achievement that never had a cycle (J6).
6. iOS ban: member disappears from the list; they are not banned (J10).
7. Web leave: sidebar removes the room before `left_at` is written. Error rolls that back. If the user leaves the page first, they can think they left when the row is still active.

Likes, follows, and most deletes are not silent. Web and iOS like/follow roll back the optimistic count (unique-violation stays liked). iOS comments remove the optimistic bubble; web shows `sync_status: "failed"`. iOS trade/post delete puts the row back if the server throws. Web trade delete waits for `delete_own_trade`. Achievement delete on iOS waits for the server.

## 16. Web versus iOS authoritative sources

| Feature | Web source | iOS source | Match? |
|---|---|---|---|
| TraxPro access | `GET /api/billing/entitlement` snapshot; some UI still uses `isProActive` (no Apple) | Server `serverTraxProActive` from the same snapshot | Shared contract. Unsafe only where web uses `isProActive` alone. |
| Owner trades | `rpc_v1_trades_owner_rows`, errors swallowed into cache/`[]` | Same RPC, throws; mapping can drop rows | Same RPC, different failure UX (J9). |
| Room join / leave | Soft `left_at` | Hard delete + insert | **Mismatch (J1).** |
| Room share URL | `/room/{slug}` after the last pass | `/room/{slug}` | Match. |
| Payout record | `record_account_payout`; web share does not write cycle id | Same RPC; treats return as the **closed** cycle | **Mismatch (J4).** |
| Payout money | `Number()` | `Decimal` | **Mismatch (M4).** |
| Expenses | Integer cents / `numeric(14,2)` | `Decimal` 2 places | Match. |
| Profile photo crop | Web now reads `image_crop` when `normalized_crop` is present | iOS `ContentImagePresentation` | Match for legacy cropped rows. New uploads bake pixels and store null crop. |
| Dashboard window | REST fallback 500 trades; V3 RPC separate | GRDB + revision reconcile | Different caches. V3 should stay. |

## 17. Ranked by actual user impact

Use this order when deciding what to fix first for people using the product today. Theoretical severity is in sections 2–5.

1. **C1 private rooms** — unauthorized read/join for every private room. Happens as soon as someone has a link or queries `rooms`.
2. **C3 accounts RLS** — if live RLS is off, every account row is readable. Confirm in production before anything else.
3. **J3 web signup `is_pro`** — every new web user, if the insert is accepted.
4. **J1 web leave / iOS join** — every dual-app member who leaves on web.
5. **J2 Tradovate silent trade miss** — every connected Tradovate account on a failed trade write.
6. **C2 / J8 charged or “subscribed” without a real entitlement write** — anyone who uses Settings/Pricing checkout.
7. **J4 + H5 payout achievement / cycle mix-up** — every iOS payout share; delete can then remove the wrong achievement.
8. **H1 leftover `trial_end`** — anyone who cancels a trial, once enforcement is on.
9. **J5 duplicate cycle 1** — every first payout.
10. **J6 / J7 / J9 / J10** — narrower paths (share-payout rollback, missing profile row, RPC swallow, ban swallow).
11. **App Store** — privacy purchase-history declaration (likely), IAP id mismatch and Apple first-grant (only if the iOS paywall is turned on). Not a blocker for a free app with StoreKit hidden.

Permanent data loss in this list: H5 / J4 can delete the wrong achievement and its social post. J2 loses trades that should have been created, not existing journal rows. J9 is display-only. CSV re-import (M2) inflates P&L rather than deleting it.

## 18. Journeys that stay consistent

- **Onboarding flag vs avatar:** both clients upload the avatar, then write `onboarding_completed` with `avatar_url`. A failed upload does not set the flag. Web still has J7 if the profile row is missing.
- **Likes, follows, comments, most deletes:** optimistic updates roll back or wait for the server.
- **Free vs Pro with flags defaulting false:** no second paywall. Completed onboarding is subscription-exempt.
- **Room ban then join (when the ban row exists):** insert and clearing `left_at` both check `is_room_banned`.
- **Payout cycle RPC itself:** close, new open cycle, and remembered drawdown preference commit together. iOS does not show payout success if that RPC throws (the id it then stores is still the wrong cycle — J4).
- **Room-join notification:** community can call it twice; `notifications_room_join_unique_idx` makes the second insert a duplicate and push is not scheduled on `23505`.

## Items checked and not reported as defects

- Legacy `/finish-trial` wall blocking free users. It does not.
- Creator codes reusable, unexpired, or client-callable. They are not, given the current grants.
- Expense or income rows changing trading P&L. They do not.
- Creating an account inserting two purchase expenses. It does not.
- Broker disconnect deleting imported trades. It does not.
- iOS sending users to Stripe Checkout for digital unlocks. It does not.
- Service-role or secret Stripe keys in client code. None found.
- Cron routes without `CRON_SECRET`. All three check it.
