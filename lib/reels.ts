import type { SupabaseClient } from "@supabase/supabase-js"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  captureReelVideoThumbnail,
  reelPublicUrlToStoragePath,
  uploadReelThumbnailBlob,
  uploadReelVideoFile,
  validateReelVideoFile,
} from "@/lib/reelVideo"

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

export const PROFILE_REELS_SELECT =
  `id, user_id, caption, video_url, thumbnail_url, duration_seconds, visibility, trade_id, kind, created_at, updated_at, trades(${REEL_TRADE_JOIN_SELECT})`

export const FEED_REELS_SELECT =
  `id, user_id, caption, video_url, thumbnail_url, duration_seconds, visibility, trade_id, kind, created_at, profiles(username, avatar_url), trades(${REEL_TRADE_JOIN_SELECT})`

export type PublishReelInput = {
  userId: string
  file: File
  caption?: string | null
  visibility?: ReelVisibility
}

export type PublishTradeReelInput = {
  tradeId: string
  userId: string
  file: File
  kind?: string | null
}

function normalizeTradeJoin(
  trades: ReelRow["trades"]
): LinkedTradeSummary | null {
  if (!trades) return null
  const row = Array.isArray(trades) ? trades[0] : trades
  if (!row?.id) return null
  return row
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
  if (thumbPath) paths.push(thumbPath)
  if (paths.length === 0) return

  const { error } = await supabase.storage.from("reels").remove(paths)
  if (error) {
    console.error("[deleteReelStorageFiles]", error)
  }
}

export async function publishReel(
  supabase: SupabaseClient,
  input: PublishReelInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    return { error: validationError.message }
  }

  let thumbnailBlob: Blob
  let durationSeconds: number

  try {
    const captured = await captureReelVideoThumbnail(input.file)
    thumbnailBlob = captured.blob
    durationSeconds = captured.metadata.durationSeconds
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file
  )
  if ("error" in videoUpload) {
    return { error: videoUpload.error }
  }

  const thumbUpload = await uploadReelThumbnailBlob(
    supabase,
    input.userId,
    thumbnailBlob
  )
  if ("error" in thumbUpload) {
    return { error: thumbUpload.error }
  }

  const caption = input.caption?.trim() ?? ""

  const { data, error } = await supabase
    .from("reels")
    .insert({
      user_id: input.userId,
      caption: caption || null,
      video_url: videoUpload.publicUrl,
      thumbnail_url: thumbUpload.publicUrl,
      duration_seconds: durationSeconds,
      visibility: input.visibility ?? "public",
      trade_id: null,
      kind: null,
    })
    .select(PROFILE_REELS_SELECT)
    .single()

  if (error) {
    return { error: handleSupabaseError(error) }
  }

  return { reel: data as ReelRow }
}

/** Attach a reel to an existing trade. Caption and visibility inherit from trade. */
export async function publishTradeReel(
  supabase: SupabaseClient,
  input: PublishTradeReelInput
): Promise<{ reel: ReelRow } | { error: string }> {
  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    return { error: validationError.message }
  }

  const { data: existing } = await supabase
    .from("reels")
    .select("id")
    .eq("trade_id", input.tradeId)
    .limit(1)
    .maybeSingle()

  if (existing?.id) {
    return { error: "This trade already has a replay attached." }
  }

  let thumbnailBlob: Blob
  let durationSeconds: number

  try {
    const captured = await captureReelVideoThumbnail(input.file)
    thumbnailBlob = captured.blob
    durationSeconds = captured.metadata.durationSeconds
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file
  )
  if ("error" in videoUpload) {
    return { error: videoUpload.error }
  }

  const thumbUpload = await uploadReelThumbnailBlob(
    supabase,
    input.userId,
    thumbnailBlob
  )
  if ("error" in thumbUpload) {
    return { error: thumbUpload.error }
  }

  const { data, error } = await supabase
    .from("reels")
    .insert({
      user_id: input.userId,
      trade_id: input.tradeId,
      kind: input.kind?.trim() || null,
      caption: null,
      video_url: videoUpload.publicUrl,
      thumbnail_url: thumbUpload.publicUrl,
      duration_seconds: durationSeconds,
      visibility: "public",
    })
    .select(PROFILE_REELS_SELECT)
    .single()

  if (error) {
    return { error: handleSupabaseError(error) }
  }

  return { reel: data as ReelRow }
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

  if (error) {
    console.error("[fetchTradeReel]", error)
    return null
  }

  return (data as ReelRow | null) ?? null
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

  if (error) {
    console.error("[fetchReelsByTradeIds]", error)
    return new Map()
  }

  const map = new Map<string, ReelRow>()
  for (const row of (data ?? []) as ReelRow[]) {
    if (row.trade_id) {
      map.set(String(row.trade_id), row)
    }
  }
  return map
}

export async function replaceTradeReelVideo(
  supabase: SupabaseClient,
  input: { reelId: string; userId: string; file: File }
): Promise<{ reel: ReelRow } | { error: string }> {
  const validationError = validateReelVideoFile(input.file)
  if (validationError) {
    return { error: validationError.message }
  }

  const { data: existing, error: fetchError } = await supabase
    .from("reels")
    .select(PROFILE_REELS_SELECT)
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .maybeSingle()

  if (fetchError || !existing) {
    return { error: "Replay not found." }
  }

  if (!isTradeAttachedReel(existing as ReelRow)) {
    return { error: "Only trade replays can be replaced this way." }
  }

  let thumbnailBlob: Blob
  let durationSeconds: number

  try {
    const captured = await captureReelVideoThumbnail(input.file)
    thumbnailBlob = captured.blob
    durationSeconds = captured.metadata.durationSeconds
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Could not process this video."
    return { error: message }
  }

  const videoUpload = await uploadReelVideoFile(
    supabase,
    input.userId,
    input.file
  )
  if ("error" in videoUpload) {
    return { error: videoUpload.error }
  }

  const thumbUpload = await uploadReelThumbnailBlob(
    supabase,
    input.userId,
    thumbnailBlob
  )
  if ("error" in thumbUpload) {
    return { error: thumbUpload.error }
  }

  await deleteReelStorageFiles(supabase, existing as ReelRow)

  const { data, error } = await supabase
    .from("reels")
    .update({
      video_url: videoUpload.publicUrl,
      thumbnail_url: thumbUpload.publicUrl,
      duration_seconds: durationSeconds,
    })
    .eq("id", input.reelId)
    .eq("user_id", input.userId)
    .select(PROFILE_REELS_SELECT)
    .single()

  if (error) {
    return { error: handleSupabaseError(error) }
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
    .select(PROFILE_REELS_SELECT)
    .single()

  if (error) {
    return { error: handleSupabaseError(error) }
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
    return { error: handleSupabaseError(fetchError) }
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
    return { error: handleSupabaseError(error) }
  }

  return { ok: true }
}
