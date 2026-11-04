import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import type {
  CopyTradeWireRow,
  TradesPageListItem,
} from "@/lib/copyTradePresentation"

type TradeScreenshotSource = {
  image_url?: string | null
}

function asScreenshotSource(
  trade: CopyTradeWireRow
): TradeScreenshotSource {
  return trade as TradeScreenshotSource
}

/** Public screenshot URLs for a trade row (extensible if multi-image is added later). */
export function tradeScreenshotPublicUrls(
  trade: TradeScreenshotSource | null | undefined
): string[] {
  if (!trade) return []
  const primary = tradeScreenshotPublicUrl(trade.image_url)
  return primary ? [primary] : []
}

export function tradeHasScreenshotForPhotosGrid(
  trade: TradeScreenshotSource | null | undefined
): boolean {
  return tradeScreenshotPublicUrls(trade).length > 0
}

export type TradesPagePhotoGridEntry = {
  key: string
  trade: Record<string, unknown>
  previewUrl: string
  imageUrls: string[]
}

/** Desktop Trades → Photos tab: first paint and each Load More step. */
export const TRADES_PAGE_PHOTOS_INITIAL_VISIBLE = 6
export const TRADES_PAGE_PHOTOS_LOAD_MORE_STEP = 8

export function tradesPagePhotoGridEntries(
  items: TradesPageListItem[]
): TradesPagePhotoGridEntry[] {
  const out: TradesPagePhotoGridEntry[] = []
  for (const item of items) {
    const tradeRow =
      item.kind === "copyGroup" ? item.representative : item.trade
    const imageUrls = tradeScreenshotPublicUrls(asScreenshotSource(tradeRow))
    if (imageUrls.length === 0) continue
    const tradeId = String(tradeRow.id ?? "").trim()
    const key =
      item.kind === "copyGroup"
        ? `copy-${String(item.batchKey)}`
        : tradeId || `trade-${out.length}`
    out.push({
      key,
      trade: tradeRow as Record<string, unknown>,
      previewUrl: imageUrls[0]!,
      imageUrls,
    })
  }
  return out
}
