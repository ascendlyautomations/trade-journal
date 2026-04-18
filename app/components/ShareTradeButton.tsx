"use client"

import { useCallback, useId, useRef, useState } from "react"
import { toPng } from "html-to-image"
import TradeShareCard from "./TradeShareCard"

function slugPart(raw: string): string {
  const s = raw.replace(/[^a-zA-Z0-9_-]/g, "")
  return s || "trade"
}

export type ShareTradeButtonProps = {
  trade: any
  className?: string
  /** Compact 📤 icon for toolbar (between edit/delete) */
  variant?: "full" | "icon"
}

export default function ShareTradeButton({
  trade,
  className = "",
  variant = "full",
}: ShareTradeButtonProps) {
  const [busy, setBusy] = useState(false)
  const lockRef = useRef(false)
  const instanceId = useId().replace(/:/g, "")
  const exportDomId = `trade-share-export-${
    trade?.id != null ? String(trade.id) : instanceId
  }`

  const handleClick = useCallback(
    async (e: React.MouseEvent) => {
      e.stopPropagation()
      e.preventDefault()
      if (lockRef.current) return
      lockRef.current = true

      const root = document.getElementById(exportDomId)
      if (!root) {
        console.error("ShareTradeButton: export root missing")
        lockRef.current = false
        return
      }

      setBusy(true)
      try {
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
          backgroundColor: "#0a0f1c",
        })

        const link = document.createElement("a")
        const ticker = slugPart(String(trade.ticker ?? "trade"))
        const idBit =
          trade.id != null ? String(trade.id).slice(0, 10) : "export"
        link.download = `trade-${ticker}-${idBit}.png`
        link.href = dataUrl
        link.click()
      } catch (err) {
        console.error("Share trade image:", err)
      } finally {
        lockRef.current = false
        setBusy(false)
      }
    },
    [trade, exportDomId]
  )

  return (
    <>
      <div
        className="pointer-events-none fixed left-[-12000px] top-0 z-[1]"
        aria-hidden
      >
        <TradeShareCard trade={trade} exportId={exportDomId} />
      </div>
      <button
        type="button"
        disabled={busy}
        title={variant === "icon" ? "Share trade" : undefined}
        aria-label={variant === "icon" ? "Share trade" : undefined}
        onClick={(e) => void handleClick(e)}
        className={
          className.trim() ||
          (variant === "icon"
            ? "rounded-lg bg-white/10 px-2 py-1 text-base leading-none text-white transition hover:bg-white/20 disabled:opacity-60"
            : "rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-white/10 disabled:opacity-60")
        }
      >
        {busy ? (variant === "icon" ? "…" : "Saving…") : variant === "icon" ? "📤" : "Share Trade"}
      </button>
    </>
  )
}
