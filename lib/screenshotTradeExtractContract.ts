/**
 * Versioned strict contract for screenshot trade extraction (Phase 3).
 * Server validates model output before returning to native.
 */

export const SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION = "v1" as const

export type ScreenshotFieldProvenance = "observed" | "inferred" | "missing"

export type ScreenshotTradeExtractContentType =
  | "executions"
  | "completedTrades"
  | "mixed"
  | "none"
  | "unrelated"

export type ScreenshotTradeField<T> = {
  value: T | null
  provenance: ScreenshotFieldProvenance
}

export type ScreenshotTradeExtractionFillV1 = {
  symbol: ScreenshotTradeField<string>
  side: ScreenshotTradeField<"buy" | "sell">
  quantity: ScreenshotTradeField<number>
  price: ScreenshotTradeField<number>
  executedAt: ScreenshotTradeField<string>
  executionID?: ScreenshotTradeField<string>
  orderID?: ScreenshotTradeField<string>
  reportedPnL?: ScreenshotTradeField<number>
  fees?: ScreenshotTradeField<number>
  sourceImageIndex: number
  warnings?: string[]
}

export type ScreenshotTradeExtractionCompletedTradeV1 = {
  symbol: ScreenshotTradeField<string>
  side: ScreenshotTradeField<"long" | "short">
  quantity: ScreenshotTradeField<number>
  entryPrice: ScreenshotTradeField<number>
  exitPrice: ScreenshotTradeField<number>
  entryAt: ScreenshotTradeField<string>
  exitAt?: ScreenshotTradeField<string>
  reportedPnL?: ScreenshotTradeField<number>
  points?: ScreenshotTradeField<number>
  executionID?: ScreenshotTradeField<string>
  orderID?: ScreenshotTradeField<string>
  sourceImageIndex: number
  warnings?: string[]
}

export type ScreenshotTradeExtractionScreenshotResultV1 = {
  index: number
  tradeLike: boolean
  warnings: string[]
}

export type ScreenshotTradeExtractionResponseV1 = {
  schemaVersion: typeof SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION
  detectedPlatform: string | null
  contentType: ScreenshotTradeExtractContentType
  fills: ScreenshotTradeExtractionFillV1[]
  completedTrades: ScreenshotTradeExtractionCompletedTradeV1[]
  warnings: string[]
  screenshotResults: ScreenshotTradeExtractionScreenshotResultV1[]
}

export type ScreenshotTradeExtractRequestV1 = {
  schemaVersion: typeof SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION
  requestFingerprint?: string
  detectedPlatformHint?: string | null
  deterministicWarnings?: string[]
  screenshots: Array<{
    index: number
    mimeType: "image/jpeg" | "image/png"
    base64: string
    ocrBlocks?: Array<{
      text: string
      x: number
      y: number
      width: number
      height: number
    }>
  }>
}

const PROVENANCE = new Set<ScreenshotFieldProvenance>([
  "observed",
  "inferred",
  "missing",
])

const CONTENT_TYPES = new Set<ScreenshotTradeExtractContentType>([
  "executions",
  "completedTrades",
  "mixed",
  "none",
  "unrelated",
])

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function parseField<T>(
  raw: unknown,
  validate: (value: unknown) => value is T
): ScreenshotTradeField<T> | null {
  if (!isRecord(raw)) return null
  const provenance = raw.provenance
  if (typeof provenance !== "string" || !PROVENANCE.has(provenance as ScreenshotFieldProvenance)) {
    return null
  }
  const value = raw.value
  if (value === null || value === undefined) {
    return { value: null, provenance: provenance as ScreenshotFieldProvenance }
  }
  if (!validate(value)) return null
  return { value, provenance: provenance as ScreenshotFieldProvenance }
}

function parseStringField(raw: unknown): ScreenshotTradeField<string> | null {
  return parseField(raw, (v): v is string => typeof v === "string")
}

function parseNumberField(raw: unknown): ScreenshotTradeField<number> | null {
  return parseField(raw, (v): v is number => typeof v === "number" && Number.isFinite(v))
}

function parseSideField(raw: unknown): ScreenshotTradeField<"buy" | "sell"> | null {
  return parseField(raw, (v): v is "buy" | "sell" => v === "buy" || v === "sell")
}

function parseTradeSideField(
  raw: unknown
): ScreenshotTradeField<"long" | "short"> | null {
  return parseField(raw, (v): v is "long" | "short" => v === "long" || v === "short")
}

function parseOptionalStringField(
  raw: unknown
): ScreenshotTradeField<string> | undefined {
  if (raw === undefined) return undefined
  return parseStringField(raw) ?? undefined
}

function parseOptionalNumberField(
  raw: unknown
): ScreenshotTradeField<number> | undefined {
  if (raw === undefined) return undefined
  return parseNumberField(raw) ?? undefined
}

function parseWarnings(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  return raw
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 12)
}

function parseFill(raw: unknown): ScreenshotTradeExtractionFillV1 | null {
  if (!isRecord(raw)) return null
  const symbol = parseStringField(raw.symbol)
  const side = parseSideField(raw.side)
  const quantity = parseNumberField(raw.quantity)
  const price = parseNumberField(raw.price)
  const executedAt = parseStringField(raw.executedAt)
  const sourceImageIndex = raw.sourceImageIndex
  if (
    !symbol ||
    !side ||
    !quantity ||
    !price ||
    !executedAt ||
    typeof sourceImageIndex !== "number" ||
    !Number.isInteger(sourceImageIndex) ||
    sourceImageIndex < 0
  ) {
    return null
  }
  return {
    symbol,
    side,
    quantity,
    price,
    executedAt,
    executionID: parseOptionalStringField(raw.executionID),
    orderID: parseOptionalStringField(raw.orderID),
    reportedPnL: parseOptionalNumberField(raw.reportedPnL),
    fees: parseOptionalNumberField(raw.fees),
    sourceImageIndex,
    warnings: parseWarnings(raw.warnings),
  }
}

function parseCompletedTrade(
  raw: unknown
): ScreenshotTradeExtractionCompletedTradeV1 | null {
  if (!isRecord(raw)) return null
  const symbol = parseStringField(raw.symbol)
  const side = parseTradeSideField(raw.side)
  const quantity = parseNumberField(raw.quantity)
  const entryPrice = parseNumberField(raw.entryPrice)
  const exitPrice = parseNumberField(raw.exitPrice)
  const entryAt = parseStringField(raw.entryAt)
  const sourceImageIndex = raw.sourceImageIndex
  if (
    !symbol ||
    !side ||
    !quantity ||
    !entryPrice ||
    !exitPrice ||
    !entryAt ||
    typeof sourceImageIndex !== "number" ||
    !Number.isInteger(sourceImageIndex) ||
    sourceImageIndex < 0
  ) {
    return null
  }
  return {
    symbol,
    side,
    quantity,
    entryPrice,
    exitPrice,
    entryAt,
    exitAt: parseOptionalStringField(raw.exitAt),
    reportedPnL: parseOptionalNumberField(raw.reportedPnL),
    points: parseOptionalNumberField(raw.points),
    executionID: parseOptionalStringField(raw.executionID),
    orderID: parseOptionalStringField(raw.orderID),
    sourceImageIndex,
    warnings: parseWarnings(raw.warnings),
  }
}

function parseScreenshotResult(
  raw: unknown
): ScreenshotTradeExtractionScreenshotResultV1 | null {
  if (!isRecord(raw)) return null
  const index = raw.index
  const tradeLike = raw.tradeLike
  if (typeof index !== "number" || !Number.isInteger(index) || index < 0) return null
  if (typeof tradeLike !== "boolean") return null
  return {
    index,
    tradeLike,
    warnings: parseWarnings(raw.warnings),
  }
}

export function validateScreenshotTradeExtractionResponse(
  raw: unknown
): ScreenshotTradeExtractionResponseV1 | null {
  if (!isRecord(raw)) return null
  if (raw.schemaVersion !== SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION) return null
  const contentType = raw.contentType
  if (typeof contentType !== "string" || !CONTENT_TYPES.has(contentType as ScreenshotTradeExtractContentType)) {
    return null
  }
  const fillsRaw = Array.isArray(raw.fills) ? raw.fills : []
  const completedRaw = Array.isArray(raw.completedTrades) ? raw.completedTrades : []
  const screenshotResultsRaw = Array.isArray(raw.screenshotResults)
    ? raw.screenshotResults
    : []

  const fills = fillsRaw
    .map(parseFill)
    .filter((item): item is ScreenshotTradeExtractionFillV1 => item !== null)
    .slice(0, 200)
  const completedTrades = completedRaw
    .map(parseCompletedTrade)
    .filter((item): item is ScreenshotTradeExtractionCompletedTradeV1 => item !== null)
    .slice(0, 200)
  const screenshotResults = screenshotResultsRaw
    .map(parseScreenshotResult)
    .filter((item): item is ScreenshotTradeExtractionScreenshotResultV1 => item !== null)
    .slice(0, 12)

  return {
    schemaVersion: SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
    detectedPlatform:
      typeof raw.detectedPlatform === "string"
        ? raw.detectedPlatform.trim().slice(0, 64) || null
        : null,
    contentType: contentType as ScreenshotTradeExtractContentType,
    fills,
    completedTrades,
    warnings: parseWarnings(raw.warnings).slice(0, 20),
    screenshotResults,
  }
}

export function validateScreenshotTradeExtractRequest(
  raw: unknown
): ScreenshotTradeExtractRequestV1 | null {
  if (!isRecord(raw)) return null
  if (raw.schemaVersion !== SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION) return null
  if (!Array.isArray(raw.screenshots) || raw.screenshots.length === 0) return null

  const screenshots = raw.screenshots
    .slice(0, 8)
    .map((item) => {
      if (!isRecord(item)) return null
      const index = item.index
      const mimeType = item.mimeType
      const base64 = item.base64
      if (
        typeof index !== "number" ||
        !Number.isInteger(index) ||
        index < 0 ||
        (mimeType !== "image/jpeg" && mimeType !== "image/png") ||
        typeof base64 !== "string" ||
        base64.length === 0
      ) {
        return null
      }
      const ocrBlocks = Array.isArray(item.ocrBlocks)
        ? item.ocrBlocks
            .slice(0, 400)
            .map((block) => {
              if (!isRecord(block)) return null
              const text = typeof block.text === "string" ? block.text.trim() : ""
              const x = block.x
              const y = block.y
              const width = block.width
              const height = block.height
              if (
                !text ||
                typeof x !== "number" ||
                typeof y !== "number" ||
                typeof width !== "number" ||
                typeof height !== "number"
              ) {
                return null
              }
              return { text: text.slice(0, 240), x, y, width, height }
            })
            .filter((block): block is NonNullable<typeof block> => block !== null)
        : undefined
      return {
        index,
        mimeType,
        base64,
        ocrBlocks,
      }
    })
    .filter((item): item is NonNullable<typeof item> => item !== null)

  if (screenshots.length === 0) return null

  return {
    schemaVersion: SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
    requestFingerprint:
      typeof raw.requestFingerprint === "string"
        ? raw.requestFingerprint.slice(0, 128)
        : undefined,
    detectedPlatformHint:
      typeof raw.detectedPlatformHint === "string"
        ? raw.detectedPlatformHint.slice(0, 64)
        : null,
    deterministicWarnings: parseWarnings(raw.deterministicWarnings),
    screenshots,
  }
}
