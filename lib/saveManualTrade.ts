import type { SupabaseClient } from "@supabase/supabase-js"
import { ensureManualUserAccountRegistered } from "@/lib/ensureManualUserAccount"
import { getSessionFromDate } from "@/lib/getSession"
import { buildDateTime } from "@/lib/inputTradeDateTime"
import { prependTradeInCache } from "@/lib/appDataCache"
import { isProActive } from "@/lib/subscription"
import { parseOptionalRr } from "@/lib/tradeRr"
import { compressScreenshot } from "@/lib/compressImage"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressOptions } from "@/lib/uploadProgress/types"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export type ManualTradeAccount = {
  name: string
  size: string
  id: string
  account_number?: string | null
  mode: string
  category?: string | null
}

export type SaveManualTradeInput = {
  ticker: string
  direction?: string
  pnl: number
  points: number
  contracts: number
  entryDate: string
  exitDate: string
  entryTime?: string
  exitTime?: string
  entryPrice?: number | null
  exitPrice?: number | null
  rr?: number | null
  publicDescription?: string
  isPublic: boolean
  imageFile?: File | null
}

export type SaveManualTradeResult =
  | { ok: true; trade: Record<string, unknown>; posted: boolean }
  | {
      ok: false
      code:
        | "auth"
        | "account_locked"
        | "account_limit"
        | "upload"
        | "save"
        | "post"
      message: string
    }

function inferDirection(
  entryPrice: number | null | undefined,
  exitPrice: number | null | undefined
): string {
  if (
    entryPrice != null &&
    exitPrice != null &&
    Number.isFinite(entryPrice) &&
    Number.isFinite(exitPrice)
  ) {
    return exitPrice >= entryPrice ? "Long" : "Short"
  }
  return "Long"
}

async function uploadTradeScreenshot(
  client: SupabaseClient,
  userId: string,
  file: File,
  options?: UploadProgressOptions
): Promise<{ path: string | null; error: string | null }> {
  const report = createMonotonicReporter(options?.onProgress, {
    min: 10,
    max: 65,
  })

  const validationError = validateImageUpload(file)
  if (validationError) {
    return { path: null, error: validationError }
  }

  report({ percent: 12, stage: "Processing image…" })

  let uploadFile: File = file
  if (file.type?.startsWith("image/")) {
    uploadFile = await compressScreenshot(file)
  }
  const fileName = `${userId}/${Date.now()}-${uploadFile.name}`

  report({ percent: 18, stage: "Uploading media…" })

  if (options?.onProgress) {
    const { error: upErr } = await uploadToSupabaseStorageWithProgress(
      client,
      {
        bucket: "screenshots",
        path: fileName,
        file: uploadFile,
        contentType: uploadFile.type || "image/jpeg",
        onProgress: (loaded, total) => {
          report({
            percent: mapUploadBytesToPercent(loaded, total, {
              start: 20,
              end: 65,
            }),
            stage: "Uploading media…",
          })
        },
      }
    )
    if (upErr) {
      console.error("[saveManualTrade] upload error:", upErr)
      return { path: null, error: upErr || "Could not upload image." }
    }
  } else {
    const { error: upErr } = await client.storage
      .from("screenshots")
      .upload(fileName, uploadFile)
    if (upErr) {
      console.error("[saveManualTrade] upload error:", upErr)
      return { path: null, error: upErr.message || "Could not upload image." }
    }
  }

  return { path: fileName, error: null }
}

async function resolveRowAccount(
  client: SupabaseClient,
  userId: string,
  account: ManualTradeAccount,
  _profileRow: {
    locked_account_type?: string | null
    locked_account_size?: string | null
    locked_account_name?: string | null
    locked_account_number?: string | null
  } | null,
  _userIsPro: boolean
): Promise<
  | { ok: true; rowAcct: ManualTradeAccount & { type: string } }
  | { ok: false; code: "account_locked"; message: string }
> {
  const modeLower = String(account.mode ?? "live").trim().toLowerCase()

  const rowAcct = {
    type: modeLower,
    name: String(account.name ?? "").trim() || null,
    size: String(account.size ?? "").trim() || null,
    id: account.id != null ? String(account.id).trim() || null : null,
    account_number: String(account.account_number ?? "").trim() || null,
    mode: String(account.mode ?? "live"),
    category: account.category ?? null,
  }

  return { ok: true, rowAcct }
}

/** Insert a manually entered trade (full or quick form) using the standard trades row shape. */
export async function saveManualTrade(
  client: SupabaseClient,
  userId: string,
  account: ManualTradeAccount,
  input: SaveManualTradeInput,
  options?: UploadProgressOptions
): Promise<SaveManualTradeResult> {
  const report = createMonotonicReporter(options?.onProgress, {
    min: 0,
    max: 99,
  })

  report({ percent: 5, stage: "Preparing…" })

  const { data: profileRow } = await client
    .from("profiles")
    .select(
      "is_pro, subscription_status, locked_account_type, locked_account_size, locked_account_name, locked_account_number"
    )
    .eq("id", userId)
    .maybeSingle()

  const userIsPro = isProActive(profileRow)
  const accountResolved = await resolveRowAccount(
    client,
    userId,
    account,
    profileRow,
    userIsPro
  )
  if (!accountResolved.ok) return accountResolved

  const rowAcct = accountResolved.rowAcct
  const skipAccountRegistry =
    rowAcct.type === "backtest" || rowAcct.type === "imported"

  const ensured = await ensureManualUserAccountRegistered(client, {
    userId,
    accountName: rowAcct.name ?? "",
    tradeAccountType: rowAcct.type,
    isPro: userIsPro,
    skipRegistry: skipAccountRegistry,
  })

  if (!ensured.ok) {
    return {
      ok: false,
      code: ensured.reason === "limit" ? "account_limit" : "save",
      message:
        ensured.reason === "limit"
          ? "Free plan account limit reached."
          : "Could not complete save. Please try again.",
    }
  }

  let screenshotUrl: string | null = null
  if (input.imageFile) {
    const uploaded = await uploadTradeScreenshot(
      client,
      userId,
      input.imageFile,
      options
    )
    if (uploaded.error) {
      return { ok: false, code: "upload", message: uploaded.error }
    }
    screenshotUrl = uploaded.path
  } else {
    report({ percent: 40, stage: "Saving trade…" })
  }

  report({ percent: 70, stage: "Creating trade record…" })

  const direction =
    input.direction?.trim() ||
    inferDirection(input.entryPrice, input.exitPrice)
  const entryTimeIso = buildDateTime(input.entryDate, input.entryTime ?? "")
  const exitTimeIso = buildDateTime(input.exitDate, input.exitTime ?? "")
  const sessionToSave = entryTimeIso
    ? getSessionFromDate(entryTimeIso) || "NY"
    : "NY"
  const parsedRr = parseOptionalRr(input.rr)
  const now = new Date()

  const tradeData = {
    ticker: input.ticker.trim(),
    direction,
    pnl: Number.isFinite(input.pnl) ? input.pnl : 0,
    rr: parsedRr,
    points: Number.isFinite(input.points) ? input.points : 0,
    contracts: Number.isFinite(input.contracts) ? input.contracts : 0,
    session: sessionToSave,
    notes: null,
    public_description: input.publicDescription?.trim() || "",
    image_url: screenshotUrl,
    account_name: rowAcct.name,
    account_size: rowAcct.size,
    account_id: rowAcct.id,
    mode: rowAcct.mode,
    account_category: rowAcct.category ?? null,
    account_type: rowAcct.type,
    strategy: null,
    user_id: userId,
    created_at: now.toISOString(),
    date: now.toISOString(),
    trade_date: input.entryDate,
    entry_price:
      input.entryPrice != null && Number.isFinite(input.entryPrice)
        ? input.entryPrice
        : null,
    exit_price:
      input.exitPrice != null && Number.isFinite(input.exitPrice)
        ? input.exitPrice
        : null,
    entry_time: entryTimeIso,
    exit_time: exitTimeIso,
    psychology_notes: null,
    trade_type: null,
    confidence: null,
    emotion: null,
    followed_plan: false,
    mistake_type: null,
    market_condition: null,
    news_event: false,
    timeframe: null,
    is_public: input.isPublic,
  }

  const { data: newTradeData, error } = await client
    .from("trades")
    .insert([tradeData])
    .select()
    .single()

  if (error) {
    console.error("[saveManualTrade] insert error:", error)
    return {
      ok: false,
      code: "save",
      message: handleSupabaseError(error),
    }
  }

  if (newTradeData) {
    prependTradeInCache(userId, newTradeData)
  }

  if (input.isPublic && newTradeData) {
    report({ percent: 85, stage: "Publishing…" })
    const { error: postError } = await client.from("posts").insert([
      {
        user_id: userId,
        trade_id: newTradeData.id,
        image_url: screenshotUrl,
        pnl: tradeData.pnl,
        rr: parsedRr,
        caption: "",
      },
    ])
    if (postError) {
      console.error("[saveManualTrade] post insert error:", postError)
      return {
        ok: false,
        code: "post",
        message: handleSupabaseError(postError),
      }
    }
    return { ok: true, trade: newTradeData, posted: true }
  }

  report({ percent: 95, stage: "Finishing…" })
  return { ok: true, trade: newTradeData, posted: false }
}

export function validateQuickTradeInput(input: {
  ticker: string
  pnl: string
  points: string
  contracts: string
}): string | null {
  if (!input.ticker.trim()) return "Symbol is required."
  const pnl = Number(String(input.pnl).replace(/,/g, ""))
  if (input.pnl.trim() === "" || !Number.isFinite(pnl)) return "P&L is required."
  if (input.points.trim() === "") return "Points is required."
  const points = Number(String(input.points).replace(/,/g, ""))
  if (!Number.isFinite(points)) return "Enter a valid points value."
  const contracts = Number.parseInt(String(input.contracts).replace(/,/g, ""), 10)
  if (!Number.isFinite(contracts) || input.contracts.trim() === "") {
    return "Contracts is required."
  }
  return null
}
