"use client"

import { useCallback, useId, useRef, useState } from "react"
import { createPortal } from "react-dom"
import TradeShareCard from "./TradeShareCard"
import ShareToConversationsModal from "./ShareToConversationsModal"
import { downloadTradeShareCardPng, tradeShareExportDomId } from "@/lib/tradeShareExport"

export type ShareTradeButtonProps = {
  trade: any
  className?: string
  /** Compact 📤 icon for toolbar (between edit/delete) */
  variant?: "full" | "icon"
  /** Loaded by parent — used for affiliate code on export */
  profile?: { referral_code?: string | null } | null
  /**
   * `full` — open menu: download PNG + send in messages.
   * `message-only` — open conversation picker only (no download UI).
   */
  mode?: "full" | "message-only"
}

export default function ShareTradeButton({
  trade,
  className = "",
  variant = "full",
  profile = null,
  mode = "full",
}: ShareTradeButtonProps) {
  const [busy, setBusy] = useState(false)
  const [shareModalOpen, setShareModalOpen] = useState(false)
  const [conversationOpen, setConversationOpen] = useState(false)
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
  }, [trade, instanceId])

  const openMessageShare = useCallback(() => {
    setShareModalOpen(false)
    setConversationOpen(true)
  }, [])

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      e.preventDefault()
      if (mode === "message-only") {
        setConversationOpen(true)
        return
      }
      setShareModalOpen(true)
    },
    [mode]
  )

  const tradeIdForDm =
    trade?.id != null && String(trade.id).trim() !== ""
      ? String(trade.id)
      : null

  const shareModal =
    mode === "full" && shareModalOpen ? (
      <div
        className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm"
        onClick={() => setShareModalOpen(false)}
      >
        <div
          className="w-full max-w-sm rounded-2xl border border-white/10 bg-[#0b1f3a] p-5 shadow-2xl"
          onClick={(e) => e.stopPropagation()}
          role="dialog"
          aria-modal="true"
          aria-labelledby="share-trade-title"
        >
          <h2 id="share-trade-title" className="mb-4 text-lg font-semibold text-white">
            Share Trade
          </h2>

          <div className="flex flex-col gap-3">
            <button
              type="button"
              onClick={() => {
                void handleDownload()
                setShareModalOpen(false)
              }}
              className="w-full rounded-lg bg-green-500 py-2 font-medium text-black"
            >
              Download Image
            </button>

            <button
              type="button"
              onClick={() => openMessageShare()}
              className="w-full rounded-lg bg-white/10 py-2 text-white hover:bg-white/20"
            >
              Send in Messages
            </button>
          </div>

          <button
            type="button"
            onClick={() => setShareModalOpen(false)}
            className="mt-4 text-sm text-white/50 hover:text-white"
          >
            Cancel
          </button>
        </div>
      </div>
    ) : null

  return (
    <>
      {mode === "full" ? (
        <div
          className="pointer-events-none fixed left-[-12000px] top-0 z-[1] flex w-full justify-center px-2"
          aria-hidden
        >
          <TradeShareCard trade={trade} exportId={exportDomId} profile={profile} />
        </div>
      ) : null}

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

      {typeof document !== "undefined" && shareModal
        ? createPortal(shareModal, document.body)
        : null}

      <ShareToConversationsModal
        open={conversationOpen && Boolean(tradeIdForDm)}
        onClose={() => setConversationOpen(false)}
        title="Send trade"
        tradeId={tradeIdForDm}
      />
    </>
  )
}
