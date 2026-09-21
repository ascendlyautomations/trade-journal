/**
 * Phase 8B — ProfileTradeCard-relevant parity between V1 full row and V2 TradeSummary.
 */

import type { TradeSummaryWireV1 } from "./tradeSummaryV2Contract.ts"
import { publicAccountBadgeFromTrade } from "../publicAccountPrivacy.ts"

export type ProfileCardParityContext = {
  isOwnerViewer: boolean
}

export type ProfileCardComparableFields = {
  id: string
  ticker: string | null
  direction: string | null
  pnl: string | null
  rr: string | null
  points: string | null
  contracts: string | null
  is_public: string | null
  image_url: string | null
  image_display_mode: string | null
  mode: string | null
  account_type: string | null
  trade_mode: string | null
  duration_seconds: string | null
  duration_text: string | null
  note_preview: string | null
  public_account_badge: string | null
}

function normScalar(value: unknown): string | null {
  if (value === null || value === undefined) return null
  if (typeof value === "number" && Number.isFinite(value)) return String(value)
  const s = String(value).trim()
  return s === "" ? null : s
}

function notePreviewFromV1Row(
  row: Record<string, unknown>,
  ctx: ProfileCardParityContext
): string | null {
  if (ctx.isOwnerViewer) {
    const notes = normScalar(row.notes)
    if (!notes) return null
    return notes.length > 360 ? notes.slice(0, 360) : notes
  }
  const caption = normScalar(row.public_description)
  if (!caption) return null
  return caption.length > 360 ? caption.slice(0, 360) : caption
}

export function profileCardFieldsFromV1Row(
  row: Record<string, unknown>,
  ctx: ProfileCardParityContext
): ProfileCardComparableFields {
  return {
    id: String(row.id),
    ticker: normScalar(row.ticker),
    direction: normScalar(row.direction),
    pnl: normScalar(row.pnl),
    rr: normScalar(row.rr),
    points: normScalar(row.points),
    contracts: normScalar(row.contracts),
    is_public: normScalar(row.is_public),
    image_url: normScalar(row.image_url),
    image_display_mode: normScalar(row.image_display_mode),
    mode: normScalar(row.mode),
    account_type: normScalar(row.account_type),
    trade_mode: normScalar(row.trade_mode),
    duration_seconds: normScalar(row.duration_seconds),
    duration_text: normScalar(row.duration_text),
    note_preview: notePreviewFromV1Row(row, ctx),
    public_account_badge: publicAccountBadgeFromTrade({
      account_type: normScalar(row.account_type),
      mode: normScalar(row.mode),
    }),
  }
}

export function profileCardFieldsFromV2Summary(
  summary: TradeSummaryWireV1
): ProfileCardComparableFields {
  return {
    id: summary.id,
    ticker: normScalar(summary.ticker),
    direction: normScalar(summary.direction),
    pnl: normScalar(summary.pnl),
    rr: normScalar(summary.rr),
    points: normScalar(summary.points),
    contracts: normScalar(summary.contracts),
    is_public: normScalar(summary.is_public),
    image_url: normScalar(summary.image_url),
    image_display_mode: normScalar(summary.image_display_mode),
    mode: normScalar(summary.mode),
    account_type: normScalar(summary.account_type),
    trade_mode: normScalar(summary.trade_mode),
    duration_seconds: normScalar(summary.duration_seconds),
    duration_text: normScalar(summary.duration_text),
    note_preview: normScalar(summary.note_preview),
    public_account_badge: publicAccountBadgeFromTrade({
      account_type: normScalar(summary.account_type),
      mode: normScalar(summary.mode),
    }),
  }
}

export type ProfileParityDiff = {
  id: string
  field: keyof ProfileCardComparableFields
  v1: string | null
  v2: string | null
}

export function compareProfileCardParity(
  v1Items: Record<string, unknown>[],
  v2Items: TradeSummaryWireV1[],
  ctx: ProfileCardParityContext
): ProfileParityDiff[] {
  const diffs: ProfileParityDiff[] = []
  const n = Math.min(v1Items.length, v2Items.length)
  if (v1Items.length !== v2Items.length) {
    diffs.push({
      id: "__page__",
      field: "id",
      v1: String(v1Items.length),
      v2: String(v2Items.length),
    })
  }
  for (let i = 0; i < n; i += 1) {
    const a = profileCardFieldsFromV1Row(v1Items[i]!, ctx)
    const b = profileCardFieldsFromV2Summary(v2Items[i]!)
    if (a.id !== b.id) {
      diffs.push({ id: a.id, field: "id", v1: a.id, v2: b.id })
      continue
    }
    const keys = Object.keys(a) as (keyof ProfileCardComparableFields)[]
    for (const field of keys) {
      if (a[field] !== b[field]) {
        diffs.push({ id: a.id, field, v1: a[field], v2: b[field] })
      }
    }
  }
  return diffs
}

/** Fields intentionally absent from V2 — must not be required for parity. */
export const PROFILE_SUMMARY_REMOVED_CATEGORIES = [
  "full_notes",
  "psychology",
  "import_broker",
  "account_identifiers",
  "detail_only_columns",
] as const
