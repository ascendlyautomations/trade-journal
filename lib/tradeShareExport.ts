/** Design canvas width — export at `pixelRatio` 2 → 1080px PNG width. */
export const TRADE_SHARE_EXPORT_WIDTH = 540

/** Minimum height if layout has not resolved before capture. */
export const TRADE_SHARE_EXPORT_MIN_HEIGHT = 960

/** Must match `ShareTradeButton` / hidden `TradeShareCard` root id. */
export function tradeShareExportDomId(
  trade: { id?: unknown },
  uniqueSuffix?: string
): string {
  const tradeBit = trade?.id != null ? String(trade.id) : "trade"
  const suffix = uniqueSuffix?.trim() || "export"
  return `trade-share-export-${tradeBit}-${suffix}`
}

function logExportTarget(exportDomId: string, root: HTMLElement) {
  const style = getComputedStyle(root)
  console.log("[tradeShareExport] exportId:", exportDomId)
  console.log("[tradeShareExport] document.getElementById:", root)
  console.log("[tradeShareExport] clientWidth:", root.clientWidth)
  console.log("[tradeShareExport] clientHeight:", root.clientHeight)
  console.log("[tradeShareExport] offsetWidth:", root.offsetWidth)
  console.log("[tradeShareExport] offsetHeight:", root.offsetHeight)
  console.log("[tradeShareExport] display:", style.display)
  console.log("[tradeShareExport] visibility:", style.visibility)
}

/**
 * html-to-image reads bounding-box size. Off-screen / duplicate-id nodes often
 * resolve to 0×0 (→ 3×3 PNG). Force explicit px dimensions before capture.
 */
function ensureExportDimensions(root: HTMLElement): {
  width: number
  height: number
} {
  root.style.boxSizing = "border-box"
  root.style.width = `${TRADE_SHARE_EXPORT_WIDTH}px`
  root.style.minWidth = `${TRADE_SHARE_EXPORT_WIDTH}px`
  root.style.maxWidth = `${TRADE_SHARE_EXPORT_WIDTH}px`

  if (getComputedStyle(root).visibility === "hidden") {
    root.style.visibility = "visible"
  }

  void root.offsetHeight

  let height = root.offsetHeight
  if (height < 100) {
    root.style.minHeight = `${TRADE_SHARE_EXPORT_MIN_HEIGHT}px`
    void root.offsetHeight
    height = root.offsetHeight
  }

  return {
    width: root.offsetWidth || TRADE_SHARE_EXPORT_WIDTH,
    height: height || TRADE_SHARE_EXPORT_MIN_HEIGHT,
  }
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

  const { width, height } = ensureExportDimensions(root)
  logExportTarget(exportDomId, root)

  if (width < 100 || height < 100) {
    console.error("downloadTradeShareCardPng: export root too small", {
      exportDomId,
      width,
      height,
    })
    return
  }

  const { toPng } = await import("html-to-image")
  const dataUrl = await toPng(root, {
    width,
    height,
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
