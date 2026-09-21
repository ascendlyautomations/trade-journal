# TradeSummary V2 — server wire contract (Phase 8B)

Phase 8B introduces a **canonical list/card trade transport** distinct from full `trades` rows. Profile tab is the first consumer (`rpc_v1_profile_tab_trades_v2`). Journal, feed, and calendar migrations follow in later phases.

## Schema identifier

Each summary object includes `summary_schema: "trade_summary_v1"` (stable name for the wire shape; RPC envelope uses `contract_version: "v2"`).

## Core fields (public + owner profile tab)

| Field | Purpose |
|-------|---------|
| `id` | Trade identity |
| `user_id` | Owner profile id |
| `ticker` | Symbol headline |
| `direction` | Side chip |
| `pnl`, `rr`, `points`, `contracts` | Metrics / quantity chips |
| `entry_time`, `exit_time` | Duration chip (via entry/exit) |
| `created_at` | Profile card date line (UTC wire) |
| `is_public` | Visibility icon |
| `public_description` | Public caption source (not duplicated as full notes) |
| `note_preview` | **Viewer-aware** card note line (see below) |
| `image_url`, `image_crop`, `image_display_mode` | Thumbnail + presentation |
| `mode`, `account_type`, `trade_mode` | Public account badge + copy-traded chip |
| `duration_seconds`, `duration_text` | Duration chip fallbacks |

## Explicitly excluded

- Full `notes`
- Psychology / review columns (`confidence`, `emotion`, `psychology_notes`, …)
- Import / broker metadata
- `account_id`, `account_name`, `account_size`
- Entry/exit **prices** (not shown on ProfileTradeCard)
- `session` (ProfileTradeCard uses `showsSession: false`)

## Owner vs public/follower privacy

| Viewer | `note_preview` source | Account identifiers |
|--------|----------------------|---------------------|
| Owner (`auth.uid() = user_id`) | First 360 chars of `notes` (matches native `TradeMapper`) | **Not** included on profile tab summary (not needed for card) |
| Public / follower / anon | First 360 chars of `public_description` only | **Never** on summary wire |

`trade_summary_owner_extension_json(trades)` exists for **future owner list** migrations (`account_id` only). Do not merge into profile tab V2 payloads.

## SQL helpers

- `trade_summary_note_preview(trades, viewer uuid)`
- `trade_summary_json(trades, viewer uuid)`
- `trade_summary_owner_extension_json(trades)` — future 8D+

RLS and profile visibility gates remain in the RPC (`rpc_v1_profile_tab_trades_v2` copies V1 gate). Summary possession does **not** authorize trade detail.

## RPCs

| RPC | Role |
|-----|------|
| `rpc_v1_profile_tab_trades` | **V1** — unchanged full row (`to_jsonb(trades)`) |
| `rpc_v1_profile_tab_trades_v2` | **V2** — TradeSummary items, same pagination/engagement |
| `rpc_v1_profile_tab_trades_summary_shadow_compare` | Shadow bytes + card-field parity |

## Native / web (8B)

- Swift: decode-only `TradeSummaryWireV1` + `ProfileTabBootstrapV2` (no UI cutover).
- TypeScript: `lib/trade/tradeSummaryV2Contract.ts` + parity helpers.

Trade detail remains PostgREST `ownerJournalSelect` (Phase 8C `TradeDetailRepository`).

## Phase 8C — native detail boundary

- `TradeDetailRepository` loads authoritative detail via PostgREST `ownerJournalSelect`.
- `DetailPresentationCache.seed(_:)` stores **list seeds** only (`TradeDetailAuthority.listSeed`).
- `seedAuthoritativeDetail` stores complete detail safe for edit/detail.
- `Trade.updatedAt` is still mapped from `created_at` until `updated_at` is added to the detail select in a later migration — do not use it for stale-detail logic.
