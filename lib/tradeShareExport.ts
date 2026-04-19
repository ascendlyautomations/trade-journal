import { toPng } from "html-to-image"

/** Must match `ShareTradeButton` / hidden `TradeShareCard` root id. */
export function tradeShareExportDomId(
  trade: { id?: unknown },
  fallbackUnique?: string
): string {
  const bit =
    trade?.id != null ? String(trade.id) : fallbackUnique?.trim() || "export"
  return `trade-share-export-${bit}`
}

function slugPart(raw: string): string {
  const s = raw.replace(/[^a-zA-Z0-9_-]/g, "")
  return s || "trade"
}

/**
 * Downloads the trade share card as PNG. Expects a mounted `#trade-share-export-{id}` node.
 */
export async function downloadTradeShareCardPng(
  trade: {
    id?: unknown
    ticker?: unknown
  },
  fallbackDomIdSuffix?: string
): Promise<void> {
  const exportDomId = tradeShareExportDomId(trade, fallbackDomIdSuffix)
  const root = document.getElementById(exportDomId)
  if (!root) {
    console.error("downloadTradeShareCardPng: export root missing", exportDomId)
    return
  }

  const imgs = root.querySelectorAll("img")
  await Promise.all(
    [...imgs].map(
      (img) =>
        new Promise<void>((resolve) => {
          if (img.complete && img.naturalWidth > 0) {
            resolve()
            return
          }
          const done = () => resolve()
          img.addEventListener("load", done, { once: true })
          img.addEventListener("error", done, { once: true })
          window.setTimeout(done, 5000)
        })
    )
  )

  await new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })

  const dataUrl = await toPng(root, {
    pixelRatio: 2,
    cacheBust: true,
    backgroundColor: "#0b1a2a",
  })

  const link = document.createElement("a")
  const ticker = slugPart(String(trade.ticker ?? "trade"))
  const idBit = trade.id != null ? String(trade.id).slice(0, 10) : "export"
  link.download = `trade-${ticker}-${idBit}.png`
  link.href = dataUrl
  link.click()
}
