# TradeTraxs Pro monetization launch checklist

Production defaults keep all switches **off** until you deliberately enable them.

Authoritative flags (`app_monetization_settings`, id = 1):

| Column | Purpose |
|--------|---------|
| `web_paywall_enabled` | Stripe checkout + shared web upgrade sheet |
| `ios_paywall_enabled` | StoreKit purchases + shared iOS upgrade sheet |
| `entitlement_enforcement_enabled` | Free usage caps + Pro-feature UI gates |

Per-user overrides exist in `app_monetization_account_overrides` (App Review, etc.).

## Pre-launch verification

1. **Apple products** — Monthly / 6-month / yearly TraxPro IDs live in App Store Connect; match `TraxProProductConfiguration` / Info.plist overrides.
2. **Apple introductory offers** — 14-day free trial configured on intended products; verify in Sandbox with a fresh Apple ID.
3. **Stripe products/prices** — Price IDs match `traxProBillingPlans`; `STRIPE_TRIAL_DAYS` (default 14) verified.
4. **Production Apple credentials** — Issuer ID, key ID, private key, bundle ID env vars set on the server.
5. **Webhook health** — Stripe subscription webhooks and Apple Server Notifications processing verified in staging.
6. **Subscription sync** — iOS StoreKit JWS → `/api/apple/subscription/sync` → `apple_subscriptions` → profile entitlement smoke-tested.
7. **Database migrations** — Production (TradeTraxs): `owned_active_accounts_accept_trades` (version `20261002191034`), `free_plan_csv_import_cooldown_3_days` (`20261002200727`), `web_paywall_enabled` column on settings/overrides (DDL applied; repo file `20261002200000_web_paywall_monetization_flag.sql`).

## Recommended enable order

1. Deploy backend + web + iOS binaries that include the shared Pro gate (flags still off).
2. Verify **Mode A** (below) in production — no unexpected paywalls.
3. Enable **`web_paywall_enabled`** for internal test accounts only (override row) → Stripe trial/checkout smoke test.
4. Enable **`ios_paywall_enabled`** for App Review override user → StoreKit purchase + restore + entitlement refresh.
5. Enable **`entitlement_enforcement_enabled`** globally last (or in staging first).
6. Run **Mode B** matrix (below) in staging with flags on.
7. Enable **`web_paywall_enabled`** globally, then **`ios_paywall_enabled`**, then **`entitlement_enforcement_enabled`** when ready for launch.

Never enable enforcement before paywalls are verified — Free users would hit server limits without a purchase path.

## Mode A — monetization OFF (production default)

- Free users use trades, posts, clips, DMs, accounts, CSV, Copy Trading, AI routes without **new** coordinator paywalls.
- No automatic Stripe redirect from the shared upgrade sheet (checkout buttons disabled when paywall flags false).
- StoreKit purchase entry points remain inert when `ios_paywall_enabled` is false.

## Mode B — monetization ON (staging)

With all three flags true for a test Free account, confirm **Upgrade to TradeTraxs Pro** (not generic errors) for:

| Action | Reason |
|--------|--------|
| 4th account create | `account_count` |
| 4th manual trade / UTC day | `daily_trades` |
| 4th post / day | `daily_posts` |
| 4th clip / day | `daily_clips` |
| 26th DM / 24h | `daily_direct_messages` |
| 2nd CSV within 3 days | `csv_import_cooldown` |
| AI Analyst | `ai_analyst` |
| Backtest Lab | `backtest_lab` |
| Prop Firm | `prop_firm` |
| Copy Trading | `copy_trading` |
| Premium analytics | `premium_analytics` |
| Trading reports | `trading_reports` |
| Performance export | `performance_exports` |

Confirm **Pro / trialing** users bypass all of the above.

## Post-purchase

- iOS: entitlement must confirm via backend before unlock; safe continuations only (routes / preserved forms).
- Web: Stripe success → profile refresh → dismiss sheet; no auto-resubmit of trades, posts, DMs, or CSV commits.

## Mode B test configuration (without touching production globals)

Use `app_monetization_account_overrides` for a dedicated staging Free test user:

1. Set all three global flags **off** in production.
2. In staging (or prod with override row only), insert/update override for test user:
   - `entitlement_enforcement_enabled = true`
   - `ios_paywall_enabled = true`
   - `web_paywall_enabled = true`
3. Run the Mode B matrix below as that user.
4. Delete or disable the override row when finished.

External QA still required: App Store Connect intro offers (ASC VERIFICATION REQUIRED), Stripe live webhook latency, StoreKit Sandbox purchase on device.

---

## TURNING MONETIZATION ON

Do this only after Mode A passes in production (flags still off) and Mode B passes in staging.

1. Confirm migrations applied (owned-active trades, web paywall flag, CSV 3-day).
2. Confirm Apple TraxPro products + **14-day free intro** on monthly / 6-month / yearly (ASC VERIFICATION REQUIRED).
3. Confirm Stripe prices + trial (`STRIPE_TRIAL_DAYS`) and webhook health.
4. Deploy latest web + iOS builds (coordinator already shipped; flags still off).
5. Enable **`web_paywall_enabled`** globally (or override cohort first).
6. Smoke Stripe checkout + return URL + entitlement refresh for a test user.
7. Enable **`ios_paywall_enabled`** globally (or App Review override first).
8. Smoke StoreKit purchase, restore, and `/api/apple/subscription/sync`.
9. Enable **`entitlement_enforcement_enabled`** last.
10. Re-run Mode B matrix on staging, then spot-check production Free + Pro accounts.

Order rule: **paywalls before enforcement** so limit hits always have a purchase path.

### Rollback procedure

If subscription or paywall behavior misbehaves in production:

1. **First:** set `entitlement_enforcement_enabled = false` — stops Free caps and Pro-feature UI gates immediately; existing subscribers keep data.
2. **Second:** set `web_paywall_enabled = false` and `ios_paywall_enabled = false` — stops new upgrade sheets and checkout/StoreKit entry points.
3. Clear any test rows in `app_monetization_account_overrides` if used.
4. No code rollback required for ordinary shutdown; subscription rows and webhooks remain intact.
5. Re-enable in reverse order (paywalls → enforcement) after fix verification.
