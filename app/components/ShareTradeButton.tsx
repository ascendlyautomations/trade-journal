"use client"

import { useCallback, useId, useRef, useState } from "react"
import TradeShareCard from "./TradeShareCard"
import { downloadTradeShareCardPng, tradeShareExportDomId } from "@/lib/tradeShareExport"

export type ShareTradeButtonProps = {
  trade: any
  className?: string
  /** Compact 📤 icon for toolbar (between edit/delete) */
  variant?: "full" | "icon"
  /** Loaded by parent — used for affiliate code on export */
  profile?: { referral_code?: string | null } | null
  /**
   * When set with `onShareMenu`, click opens the menu instead of downloading immediately.
   */
  shareMenu?: boolean
  onShareMenu?: () => void
}

export default function ShareTradeButton({
  trade,
  className = "",
  variant = "full",
  profile = null,
  shareMenu = false,
  onShareMenu,
}: ShareTradeButtonProps) {
  const [busy, setBusy] = useState(false)
  const lockRef = useRef(false)
  const instanceId = useId().replace(/:/g, "")
  const exportDomId = tradeShareExportDomId(trade, instanceId)

  const handleDownload = useCallback(async () => {
    if (lockRef.current) return
    lockRef.current = true
    setBusy(true)
    try {
      await downloadTradeShareCardPng(trade, instanceId)
    } finally {
      lockRef.current = false
      setBusy(false)
    }
  }, [trade])

  const handleClick = useCallback(
    async (e: React.MouseEvent) => {
      e.stopPropagation()
      e.preventDefault()
      if (shareMenu && onShareMenu) {
        onShareMenu()
        return
      }
      await handleDownload()
    },
    [shareMenu, onShareMenu, handleDownload]
  )

  return (
    <>
      <div
        className="pointer-events-none fixed left-[-12000px] top-0 z-[1] flex w-full justify-center px-2"
        aria-hidden
      >
        <TradeShareCard trade={trade} exportId={exportDomId} profile={profile} />
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
