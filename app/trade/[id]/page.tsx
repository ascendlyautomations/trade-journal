"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Navbar from "../../components/Navbar"
import TradeSocialLayer from "../../components/TradeSocialLayer"
import { supabase } from "../../../lib/supabaseClient"

function tradeScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

export default function TradeDetailPage() {
  const params = useParams()
  const router = useRouter()
  const rawId = params.id
  const tradeId =
    typeof rawId === "string" ? rawId : Array.isArray(rawId) ? rawId[0] : ""

  const [trade, setTrade] = useState<any>(null)
  const [userId, setUserId] = useState<string | undefined>(undefined)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!tradeId) {
      setLoading(false)
      return
    }

    let cancelled = false

    ;(async () => {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (cancelled) return
      const sessionUserId = session?.user?.id
      setUserId(sessionUserId)

      const { data, error } = await supabase
        .from("trades")
        .select("*")
        .eq("id", tradeId)
        .maybeSingle()

      if (cancelled) return

      // RLS grants: owner (trades_select_own), public (trades_select_public),
      // or shared in a conversation the viewer participates in
      // (trades_select_shared_in_conversation).
      const resolvedTrade = error ? null : data

      if (error && !resolvedTrade) {
        setTrade(null)
      } else {
        setTrade(resolvedTrade)
      }
      setLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [tradeId])

  const imgSrc = trade ? tradeScreenshotSrc(trade.image_url) : null
  const pnl = trade != null ? Number(trade.pnl) : NaN
  const pnlPositive = !Number.isNaN(pnl) && pnl >= 0

  if (!tradeId) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">
          <p className="text-center text-gray-400">Invalid trade link.</p>
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          <div>Loading...</div>
        </div>
      </>
    )
  }

  if (!trade) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">
          <div className="max-w-xl mx-auto space-y-4 text-center">
            <p className="text-gray-400">This trade is unavailable.</p>
            <button
              type="button"
              onClick={() => router.push("/trades")}
              className="text-blue-400 hover:underline"
            >
              Back to trades
            </button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">
        <div className="max-w-xl mx-auto space-y-4">
          <button
            type="button"
            onClick={() => router.back()}
            className="text-sm text-gray-400 hover:text-white"
          >
            ← Back
          </button>

          <div className="rounded-xl border border-white/10 bg-white/5 overflow-hidden">
            {imgSrc ? (
              <div className="w-full bg-black/30">
                <img
                  src={imgSrc}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  className="w-full max-h-[400px] object-cover block"
                />
              </div>
            ) : null}
            <div className="p-4 space-y-2">
              <div className="flex justify-between items-center gap-4">
                <div>
                  <p className="text-lg font-semibold">{trade.ticker}</p>
                  <p className="text-xs text-gray-400">{trade.direction}</p>
                </div>
                <span
                  className={`text-sm font-semibold tabular-nums ${
                    pnlPositive ? "text-emerald-400" : "text-red-400"
                  }`}
                >
                  {Number.isNaN(pnl)
                    ? `—`
                    : `${pnlPositive ? "+" : "-"}$${Math.abs(pnl)}`}
                </span>
              </div>
              {trade.public_description ? (
                <p className="text-sm text-gray-300 leading-relaxed">
                  {trade.public_description}
                </p>
              ) : null}
            </div>
          </div>

          <TradeSocialLayer
            tradeId={tradeId}
            currentUserId={userId}
            tradeOwnerUserId={trade.user_id}
          />
        </div>
      </div>
    </>
  )
}
