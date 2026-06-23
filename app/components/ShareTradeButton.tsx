"use client"

import { useCallback, useId, useRef, useState } from "react"
import { createPortal } from "react-dom"
import TradeShareCard from "./TradeShareCard"
import ShareToConversationsModal from "./ShareToConversationsModal"
import {
  downloadTradeShareCardPng,
  TRADE_SHARE_EXPORT_WIDTH,
  tradeShareExportDomId,
} from "@/lib/tradeShareExport"

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
  /** When set, parent owns the send-to-DMs UI (no in-component picker). */
  onSendClick?: () => void
}

export default function ShareTradeButton({
  trade,
  className = "",
  variant = "full",
  profile = null,
  mode = "full",
  onSendClick,
}: ShareTradeButtonProps) {
  const [busy, setBusy] = useState(false)
  const [isOpen, setIsOpen] = useState(false)
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
    setIsOpen(false)
    setConversationOpen(true)
  }, [])

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation()
      e.preventDefault()
      if (mode === "message-only") {
        if (onSendClick) {
          onSendClick()
          return
        }
        setConversationOpen(true)
        return
      }
      setIsOpen(true)
    },
    [mode, onSendClick]
  )

  const tradeIdForDm =
    trade?.id != null && String(trade.id).trim() !== ""
      ? String(trade.id)
      : null

  return (
    <>
      {mode === "full" ? (
        <div
          className="pointer-events-none fixed top-0 overflow-hidden"
          style={{
            left: 0,
            width: TRADE_SHARE_EXPORT_WIDTH,
            opacity: 0,
            zIndex: -1,
          }}
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
        onClick={handleClick}
        className={
          className.trim() ||
          "p-1 rounded-lg bg-blue-500/20 hover:bg-blue-500/30 transition"
        }
      >
        {busy ? (
          variant === "icon" ? (
            <span className="text-xs tabular-nums">…</span>
          ) : (
            "Saving…"
          )
        ) : variant === "icon" ? (
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-4 w-4 text-blue-300"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
            />
          </svg>
        ) : (
          "📤"
        )}
      </button>

      {isOpen &&
        typeof window !== "undefined" &&
        createPortal(
          <div className="fixed inset-0 z-[99999] flex items-center justify-center pointer-events-none">
            <div
              className="absolute inset-0 bg-black/60 backdrop-blur-sm pointer-events-auto"
              onClick={() => setIsOpen(false)}
            />
            <div
              className="relative z-10 w-full max-w-md bg-[#0b1f3a] rounded-2xl p-6 border border-white/10 pointer-events-auto"
              onClick={(e) => e.stopPropagation()}
            >
              <h2 id="share-trade-title" className="mb-4 text-lg font-semibold text-white">
                Share Trade
              </h2>

              <div className="flex flex-col gap-3">
                <button
                  type="button"
                  onClick={() => {
                    void handleDownload()
                    setIsOpen(false)
                  }}
                  className="w-full rounded-lg bg-green-500 py-2 font-medium text-black"
                >
                  Download Image
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setIsOpen(false)
                    if (onSendClick) {
                      onSendClick()
                      return
                    }
                    openMessageShare()
                  }}
                  className="w-full rounded-lg bg-white/10 py-2 text-white hover:bg-white/20"
                >
                  Send in Messages
                </button>
              </div>

              <button
                type="button"
                onClick={() => setIsOpen(false)}
                className="mt-4 text-sm text-white/50 hover:text-white"
              >
                Cancel
              </button>
            </div>
          </div>,
          document.body
        )}

      {!onSendClick ? (
        <ShareToConversationsModal
          open={conversationOpen && Boolean(tradeIdForDm)}
          onClose={() => setConversationOpen(false)}
          title="Send trade"
          tradeId={tradeIdForDm}
        />
      ) : null}
    </>
  )
}
