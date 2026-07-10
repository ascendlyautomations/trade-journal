import type { SupabaseClient } from "@supabase/supabase-js"
import {
  captureReelVideoThumbnail,
  readReelVideoMetadata,
  reelPublicUrlToStoragePath,
  uploadReelThumbnailBlob,
  uploadReelVideoFile,
  validateReelVideoFile,
} from "@/lib/reelVideo"
import {
  createMonotonicReporter,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressReporter } from "@/lib/uploadProgress/types"
import { invalidateUserStreaksCache } from "@/lib/userStreaksCache"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { devLog, devWarn } from "@/lib/devLog"

export type ReelVisibility = "public" | "private"

export type LinkedTradeSummary = {
  id: string
  public_description: string | null
  is_public: boolean | null
  ticker: string | null
  direction: string | null
  pnl: number | null
  rr: number | null
}

export type ReelRow = {
  id: string
  user_id: string
  caption: string | null
  video_url: string
  thumbnail_url: string
  duration_seconds: number | null
  visibility: ReelVisibility
  trade_id: string | null
  kind: string | null
  created_at: string
  updated_at: string
  trades?: LinkedTradeSummary | LinkedTradeSummary[] | null
}

export const REEL_TRADE_JOIN_SELECT =
  "id, public_description, is_public, ticker, direction, pnl, rr"

/** PostgREST FK hint for reels.trade_id → trades.id */
export const REEL_TRADE_EMBED =
  `trades!reels_trade_id_fkey(${REEL_TRADE_JOIN_SELECT})`

export const REEL_ROW_SELECT =
  "id, user_id, caption, video_url, thumbnail_url, duration_seconds, visibility, trade_id, kind, created_at, updated_at"

/** Minimal reel fields embedded on trade joins for card previews. */
export const TRADE_ATTACHED_REEL_CARD_SELECT =
  "id, user_id, video_url, thumbnail_url, duration_seconds, trade_id, visibility"

export function formatReelDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds))
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${String(secs).padStart(2, "0")}`
}

/** Reel from a trade join (`trades.reels`) or a direct reel row. */
export function resolveTradeAttachedReel(
  source:
    | { reels?: ReelRow | ReelRow[] | null }
    | ReelRow
    | null
    | undefined
): ReelRow | null {
  if (!source) return null

  if (
    "video_url" in source &&
    "thumbnail_url" in source &&
    source.id != null &&
    String(source.id).trim() !== ""
  ) {
    return source as ReelRow
  }

  const trade = source as { reels?: ReelRow | ReelRow[] | null }
  if (!trade.reels) return null
  const row = Array.isArray(trade.reels) ? trade.reels[0] : trade.reels
  if (!row?.id) return null
  return row
}

export const PROFILE_REELS_SELECT = `${REEL_ROW_SELECT}, ${REEL_TRADE_EMBED}`

export const FEED_REELS_SELECT =
  `id, user_id, caption, video_url, thumbnail_url, duration_seconds, visibility, trade_id, kind, created_at, profiles(username, avatar_url), ${REEL_TRADE_EMBED}`

type SupabaseErr = {
  message?: string
  code?: string
  details?: string
  hint?: string
}

const TRADE_REEL_LOG = "[publishTradeReel]"

function logTradeReel(step: string, detail?: Record<string, unknown>) {
  if (detail) {
    devLog(TRADE_REEL_LOG, step, detail)
  } else {
    devLog(TRADE_REEL_LOG, step)
  }
}

function logTradeReelError(step: string, error: unknown) {
  console.error(TRADE_REEL_LOG, step, error)
}

/** Surface actionable reel DB errors instead of masking them. */
export function formatReelMutationError(error: unknown): string {
  const e = error as SupabaseErr | null | undefined
  if (!e?.message) return toUserFacingErrorMessage(error)

  const msg = String(e.message)
  const lower = msg.toLowerCase()

  if (
    lower.includes("trade_id") &&
    (lower.includes("column") ||
      lower.includes("schema cache") ||
      lower.includes("could not find"))
  ) {
    return "Clip could not be saved. Apply the latest database migration (reels.trade_id) and reload the API schema."
  }

  if (e.code === "23503") {
    return "Trade not found. Save the trade first, then attach the clip."
  }

  if (e.code === "23514") {
    return "Invalid clip data for this trade."
  }

  return toUserFacingErrorMessage(error)
}

function normalizeTradeJoin(
  trades: ReelRow["trades"]
): LinkedTradeSummary | null {
  if (!trades) return null
  const row = Array.isArray(trades) ? trades[0] : trades
  if (!row?.id) return null
  return row
}

async function hydrateReelsWithTrades(
  supabase: SupabaseClient,
  reels: ReelRow[]
): Promise<ReelRow[]> {
  const tradeIds = [
    ...new Set(
      reels
        .map((row) => row.trade_id)
        .filter((id): id is string => id != null && String(id).trim() !== "")
        .map((id) => String(id))
    ),
  ]

  if (tradeIds.length === 0) return reels

  const { data: trades, error } = await supabase
    .from("trades")
    .select(REEL_TRADE_JOIN_SELECT)
    .in("id", tradeIds)

  if (error) {
    console.error("[hydrateReelsWithTrades]", error)
    return reels
  }

  const tradeMap = new Map<string, LinkedTradeSummary>()
  for (const trade of trades ?? []) {
    if (trade?.id) tradeMap.set(String(trade.id), trade as LinkedTradeSummary)
  }

  return reels.map((reel) => {
    if (!reel.trade_id || reel.trades) return reel
    const trade = tradeMap.get(String(reel.trade_id))
    return trade ? { ...reel, trades: trade } : reel
  })
}

export type PublishReelInput = {
  userId: string
  file: File
  caption?: string | null
  visibility?: ReelVisibility
  onProgress?: UploadProgressReporter
}

export type PublishTradeReelInput = {
  tradeId: string
  userId: string
  file: File
  kind?: string | null
  onProgress?: UploadProgressReporter
}

export function isTradeAttachedReel(
  reel: { trade_id?: string | null } | null | undefined
): boolean {
  const id = reel?.trade_id
  return id != null && String(id).trim() !== ""
}

export function resolveReelTradeJoin(
  reel: { trades?: ReelRow["trades"] } | null | undefined
): LinkedTradeSummary | null {
  return normalizeTradeJoin(reel?.trades ?? null)
}

/** Caption: trade public_description when attached; else reel.caption. */
export function resolveReelCaption(
  reel: {
    trade_id?: string | null
    caption?: string | null
    trades?: ReelRow["trades"]
  } | null | undefined
): string | null {
  if (!reel) return null
  if (isTradeAttachedReel(reel)) {
    const trade = resolveReelTradeJoin(reel)
    const fromTrade = trade?.public_description
    if (fromTrade == null) return null
    const trimmed = String(fromTrade).trim()
    return trimmed !== "" ? trimmed : null
  }
  const raw = reel.caption
  if (raw == null) return null
  const trimmed = String(raw).trim()
  return trimmed !== "" ? trimmed : null
}

export async function deleteReelStorageFiles(
  supabase: SupabaseClient,
  reel: { video_url?: string | null; thumbnail_url?: string | null }
): Promise<void> {
  const paths: string[] = []
  const videoPath = reelPublicUrlToStoragePath(String(reel.video_url ?? ""))
  const thumbPath = reelPublicUrlToStoragePath(String(reel.thumbnail_url ?? ""))
  if (videoPath) paths.push(videoPath)
  if (thumbPath && thumbPath !== videoPath) paths.push(thumbPath)
  if (paths.length === 0) return

  const { error } = await supabase.storage.from("reels").remove(paths)
  if (error) {
    console.error("[deleteReelStorageFiles]", error)
  }
}

/** Generate and persist a JPEG thumbnail after publish — never blocks upload. */
function scheduleReelThumbnailGeneration(
  supabase: SupabaseClient,
  input: {
    reelId: string
    userId: string
    file: File
    previousThumbnailUrl?: string | null
  }
): void {
  void (async () => {
    try {
      const captured = await captureReelVideoThumbnail(input.file)
      const thumbUpload = await uploadReelThumbnailBlob(
        supabase,
        input.userId,
        captured.blob
      )
      if ("error" in thumbUpload) {
        console.error(
          "[scheduleReelThumbnailGeneration] upload:",
          thumbUpload.error
        )
        return
      }

      const { error } = await supabase
        .from("reels")
        .update({ thumbnail_url: thumbUpload.publicUrl })
        .eq("id", input.reelId)
        .eq("user_id", input.userId)

      if (error) {
        console.error("[scheduleReelThumbnailGeneration] update:", error)
        return
      }

      const prevPath = reelPublicUrlToStoragePath(
        String(input.previousThumbnailUrl ?? "")
      )
      if (prevPath?.includes("/thumbnails/")) {
        await supabase.storage.from("reels").remove([prevPath])
      }
    } catch (err) {
      console.error("[scheduleReelThumbnailGeneration]", err)
    }
  })()
}

export async function publishReel(
  supabase: SupabaseClient,
  input: PublishReelInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const report = createMonotonicReporter(input.onProgress)
  report({ percent: 5, stage: "Preparing video…" })

  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    return { error: validationError.message }
  }

  let durationSeconds: number

  try {
    report({ percent: 8, stage: "Reading video…" })
    const metadata = await readReelVideoMetadata(input.file)
    durationSeconds = metadata.durationSeconds
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  report({ percent: 15, stage: "Uploading media…" })
  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file,
    {
      onProgress: input.onProgress
        ? (update) => {
            report({
              percent: 15 + (update.percent / 100) * 73,
              stage: update.stage || "Uploading media…",
            })
          }
        : undefined,
    }
  )
  if ("error" in videoUpload) {
    return { error: videoUpload.error }
  }

  report({ percent: 90, stage: "Creating clip…" })

  const caption = input.caption?.trim() ?? ""

  const { data, error } = await supabase
    .from("reels")
    .insert({
      user_id: input.userId,
      caption: caption || null,
      video_url: videoUpload.publicUrl,
      thumbnail_url: videoUpload.publicUrl,
      duration_seconds: durationSeconds,
      visibility: input.visibility ?? "public",
      trade_id: null,
      kind: null,
    })
    .select(REEL_ROW_SELECT)
    .single()

  if (error) {
    console.error("[publishReel] insert:", error)
    return { error: formatReelMutationError(error) }
  }

  scheduleReelThumbnailGeneration(supabase, {
    reelId: String(data.id),
    userId: input.userId,
    file: input.file,
    previousThumbnailUrl: videoUpload.publicUrl,
  })

  report({ percent: 95, stage: "Publishing…" })
  invalidateUserStreaksCache(input.userId)

  return { reel: data as ReelRow }
}

/** Attach a reel to an existing trade. Caption and visibility inherit from trade. */
export async function publishTradeReel(
  supabase: SupabaseClient,
  input: PublishTradeReelInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const report = createMonotonicReporter(input.onProgress)
  report({ percent: 5, stage: "Preparing replay…" })

  logTradeReel("start", {
    tradeId: input.tradeId,
    userId: input.userId,
    fileName: input.file.name,
    fileSize: input.file.size,
  })

  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    logTradeReelError("validation failed", validationError)
    return { error: validationError.message }
  }

  const { data: tradeRow, error: tradeError } = await supabase
    .from("trades")
    .select("id")
    .eq("id", input.tradeId)
    .eq("user_id", input.userId)
    .maybeSingle()

  if (tradeError) {
    logTradeReelError("trade lookup failed", tradeError)
    return { error: formatReelMutationError(tradeError) }
  }

  if (!tradeRow?.id) {
    logTradeReelError("trade lookup failed", {
      message: "Trade not found for user",
      tradeId: input.tradeId,
      userId: input.userId,
    })
    return { error: "Trade not found or you do not have permission to attach a replay." }
  }

  logTradeReel("trade verified", { tradeId: tradeRow.id })

  const { data: existing, error: existingError } = await supabase
    .from("reels")
    .select("id")
    .eq("trade_id", input.tradeId)
    .limit(1)
    .maybeSingle()

  if (existingError) {
    logTradeReelError("existing replay lookup failed", existingError)
    return { error: formatReelMutationError(existingError) }
  }

  if (existing?.id) {
    logTradeReel("blocked: trade already has replay", { reelId: existing.id })
    return { error: "This trade already has a replay attached." }
  }

  let durationSeconds: number

  try {
    logTradeReel("reading video metadata")
    report({ percent: 8, stage: "Reading video…" })
    const metadata = await readReelVideoMetadata(input.file)
    durationSeconds = metadata.durationSeconds
    logTradeReel("metadata read", { durationSeconds })
  } catch (err) {
    logTradeReelError("metadata read failed", err)
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  logTradeReel("video upload started")
  report({ percent: 15, stage: "Uploading media…" })
  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file,
    {
      onProgress: input.onProgress
        ? (update) => {
            report({
              percent: 15 + (update.percent / 100) * 73,
              stage: update.stage || "Uploading media…",
            })
          }
        : undefined,
    }
  )
  if ("error" in videoUpload) {
    logTradeReelError("video upload failed", { message: videoUpload.error })
    return { error: videoUpload.error }
  }
  logTradeReel("video upload complete", {
    publicUrl: videoUpload.publicUrl,
    storagePath: videoUpload.storagePath,
  })

  logTradeReel("insert started", {
    tradeId: input.tradeId,
    userId: input.userId,
  })
  report({ percent: 90, stage: "Creating clip…" })

  const { data, error } = await supabase
    .from("reels")
    .insert({
      user_id: input.userId,
      trade_id: input.tradeId,
      kind: input.kind?.trim() || null,
      caption: null,
      video_url: videoUpload.publicUrl,
      thumbnail_url: videoUpload.publicUrl,
      duration_seconds: durationSeconds,
      visibility: "public",
    })
    .select(REEL_ROW_SELECT)
    .single()

  if (error) {
    logTradeReelError("insert failed", error)
    return { error: formatReelMutationError(error) }
  }

  logTradeReel("insert succeeded", {
    reelId: data?.id,
    tradeId: data?.trade_id,
    userId: data?.user_id,
  })

  scheduleReelThumbnailGeneration(supabase, {
    reelId: String(data.id),
    userId: input.userId,
    file: input.file,
    previousThumbnailUrl: videoUpload.publicUrl,
  })

  const hydrated = await fetchTradeReel(supabase, input.tradeId)
  const reel = hydrated ?? (data as ReelRow)
  logTradeReel("complete", {
    reelId: reel.id,
    tradeId: reel.trade_id,
  })
  report({ percent: 95, stage: "Publishing…" })
  invalidateUserStreaksCache(input.userId)
  return { reel }
}

export async function fetchTradeReel(
  supabase: SupabaseClient,
  tradeId: string
): Promise<ReelRow | null> {
  const { data, error } = await supabase
    .from("reels")
    .select(PROFILE_REELS_SELECT)
    .eq("trade_id", tradeId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!error && data) {
    return data as ReelRow
  }

  if (error) {
    console.error("[fetchTradeReel] embed query:", error)
  }

  const { data: fallback, error: fallbackError } = await supabase
    .from("reels")
    .select(REEL_ROW_SELECT)
    .eq("trade_id", tradeId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (fallbackError) {
    console.error("[fetchTradeReel] fallback query:", fallbackError)
    return null
  }

  if (!fallback) return null

  const [hydrated] = await hydrateReelsWithTrades(supabase, [
    fallback as ReelRow,
  ])
  return hydrated ?? null
}

export async function fetchReelsByTradeIds(
  supabase: SupabaseClient,
  tradeIds: string[]
): Promise<Map<string, ReelRow>> {
  const ids = tradeIds.filter((id) => id != null && String(id).trim() !== "")
  if (ids.length === 0) return new Map()

  const { data, error } = await supabase
    .from("reels")
    .select(PROFILE_REELS_SELECT)
    .in("trade_id", ids)

  let rows: ReelRow[] = []

  if (!error) {
    rows = (data ?? []) as ReelRow[]
  } else {
    console.error("[fetchReelsByTradeIds] embed query:", error)
    const { data: fallback, error: fallbackError } = await supabase
      .from("reels")
      .select(REEL_ROW_SELECT)
      .in("trade_id", ids)

    if (fallbackError) {
      console.error("[fetchReelsByTradeIds] fallback query:", fallbackError)
      return new Map()
    }

    rows = await hydrateReelsWithTrades(
      supabase,
      (fallback ?? []) as ReelRow[]
    )
  }

  const map = new Map<string, ReelRow>()
  for (const row of rows) {
    if (row.trade_id) {
      map.set(String(row.trade_id), row)
    }
  }
  return map
}

export async function fetchUserProfileReels(
  supabase: SupabaseClient,
  userId: string
): Promise<ReelRow[]> {
  const { data, error } = await supabase
    .from("reels")
    .select(PROFILE_REELS_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })

  if (!error) {
    const reels = (data ?? []) as ReelRow[]
    devLog("[fetchUserProfileReels] loaded", {
      userId,
      total: reels.length,
      tradeLinked: reels.filter((row) => row.trade_id).length,
    })
    return reels
  }

  console.error("[fetchUserProfileReels] embed query:", error)

  const { data: fallback, error: fallbackError } = await supabase
    .from("reels")
    .select(REEL_ROW_SELECT)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })

  if (fallbackError) {
    console.error("[fetchUserProfileReels] fallback query:", fallbackError)
    return []
  }

  return hydrateReelsWithTrades(supabase, (fallback ?? []) as ReelRow[])
}

export async function replaceTradeReelVideo(
  supabase: SupabaseClient,
  input: {
    reelId: string
    userId: string
    file: File
    onProgress?: UploadProgressReporter
  }
): Promise<{ reel: ReelRow } | { error: string }> {
  const report = createMonotonicReporter(input.onProgress)
  report({ percent: 5, stage: "Preparing video…" })

  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    return { error: validationError.message }
  }

  const { data: existing, error: fetchError } = await supabase
    .from("reels")
    .select(REEL_ROW_SELECT)
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .maybeSingle()

  if (fetchError) {
    console.error("[replaceTradeReelVideo] fetch:", fetchError)
    return { error: formatReelMutationError(fetchError) }
  }

  if (!existing) {
    return { error: "Clip not found." }
  }

  if (!isTradeAttachedReel(existing as ReelRow)) {
    return { error: "Only trade clips can be replaced this way." }
  }

  let durationSeconds: number

  try {
    report({ percent: 8, stage: "Reading video…" })
    const metadata = await readReelVideoMetadata(input.file)
    durationSeconds = metadata.durationSeconds
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  report({ percent: 15, stage: "Uploading media…" })
  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file,
    {
      onProgress: input.onProgress
        ? (update) => {
            report({
              percent: 15 + (update.percent / 100) * 73,
              stage: update.stage || "Uploading media…",
            })
          }
        : undefined,
    }
  )
  if ("error" in videoUpload) {
    return { error: videoUpload.error }
  }

  const previousThumbnailUrl = (existing as ReelRow).thumbnail_url
  await deleteReelStorageFiles(supabase, existing as ReelRow)

  report({ percent: 90, stage: "Updating clip…" })
  const { data, error } = await supabase
    .from("reels")
    .update({
      video_url: videoUpload.publicUrl,
      thumbnail_url: videoUpload.publicUrl,
      duration_seconds: durationSeconds,
    })
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .select(REEL_ROW_SELECT)
    .single()

  if (error) {
    console.error("[replaceTradeReelVideo] update:", error)
    return { error: formatReelMutationError(error) }
  }

  scheduleReelThumbnailGeneration(supabase, {
    reelId: input.reelId,
    userId: input.userId,
    file: input.file,
    previousThumbnailUrl,
  })

  const tradeId = (existing as ReelRow).trade_id
  if (tradeId) {
    const hydrated = await fetchTradeReel(supabase, String(tradeId))
    if (hydrated) return { reel: hydrated }
  }

  return { reel: data as ReelRow }
}

export type UpdateReelCaptionInput = {
  reelId: string
  userId: string
  caption?: string | null
}

/** Update reel metadata (caption only in phase 1). Owner-only via RLS. */
export async function updateReelCaption(
  supabase: SupabaseClient,
  input: UpdateReelCaptionInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const { data: existing } = await supabase
    .from("reels")
    .select("trade_id")
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .maybeSingle()

  if (existing?.trade_id) {
    return {
      error: "Caption is edited on the trade for replays attached to trades.",
    }
  }

  const caption = input.caption?.trim() ?? ""

  const { data, error } = await supabase
    .from("reels")
    .update({ caption: caption || null })
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .select(REEL_ROW_SELECT)
    .single()

  if (error) {
    console.error("[updateReelCaption] update:", error)
    return { error: formatReelMutationError(error) }
  }

  return { reel: data as ReelRow }
}

export async function deleteReel(
  supabase: SupabaseClient,
  input: { reelId: string; userId: string }
): Promise<{ ok: true } | { error: string }> {
  const { data: existing, error: fetchError } = await supabase
    .from("reels")
    .select("id, video_url, thumbnail_url, trade_id")
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .maybeSingle()

  if (fetchError) {
    return { error: formatReelMutationError(fetchError) }
  }

  if (existing) {
    await deleteReelStorageFiles(supabase, existing)
  }

  const { error } = await supabase
    .from("reels")
    .delete()
    .eq("id", input.reelId)
    .eq("user_id", input.userId)

  if (error) {
    return { error: formatReelMutationError(error) }
  }

  return { ok: true }
}
