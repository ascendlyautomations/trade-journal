"use client"

import Link from "next/link"
import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { isProActive } from "../../lib/subscription"

export default function AnalystPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [selectedTrade, setSelectedTrade] = useState<any>(null)
  const [profile, setProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
  } | null>(null)

  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const [pageReady, setPageReady] = useState(false)

  useEffect(() => {
    void fetchTrades()
  }, [])

  async function fetchTrades() {
    setPageReady(false)
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      setPageReady(true)
      return
    }

    const [{ data }, { data: prof }] = await Promise.all([
      supabase
        .from("trades")
        .select("*")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false }),
      supabase
        .from("profiles")
        .select("is_pro, subscription_status")
        .eq("id", user.id)
        .maybeSingle(),
    ])

    setTrades(data || [])
    setProfile(prof ?? null)
  }

  function formatCurrency(val: number) {
    if (val === null || val === undefined) return "-"
    return `${val < 0 ? "-" : ""}$${Math.abs(val).toLocaleString()}`
  }

  function formatDate(date: string) {
    return new Date(date).toLocaleDateString()
  }

  async function analyzeTrade(trade: any) {
    if (!isProActive(profile)) return

    setSelectedTrade(trade)

    if (trade.ai_feedback) {
      setMessages([{ role: "assistant", content: trade.ai_feedback }])
      return
    }

    setMessages([])
    setLoading(true)

    const res = await fetch("/api/analyze-trade", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        trade,
        messages: [],
      }),
    })

    const data = await res.json()

    if (!res.ok) {
      setMessages([
        {
          role: "assistant",
          content:
            data.reply ||
            data.error ||
            "AI Analyst is a Pro feature. Upgrade to continue.",
        },
      ])
      setLoading(false)
      return
    }

    setMessages([{ role: "assistant", content: data.reply }])
    setLoading(false)
  }

  async function sendMessage() {
    if (!input.trim() || !selectedTrade) return
    if (!isProActive(profile)) return

    const newMessages = [...messages, { role: "user", content: input }]

    setMessages(newMessages)
    setInput("")
    setLoading(true)

    const res = await fetch("/api/analyze-trade", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        trade: selectedTrade,
        messages: newMessages,
      }),
    })

    const data = await res.json()

    if (!res.ok) {
      setMessages([
        ...newMessages,
        {
          role: "assistant",
          content:
            data.reply ||
            data.error ||
            "AI Analyst is a Pro feature. Upgrade to continue.",
        },
      ])
      setLoading(false)
      return
    }

    setMessages([
      ...newMessages,
      { role: "assistant", content: data.reply },
    ])

    setLoading(false)
  }

  const pro = isProActive(profile)

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-10">
        <h1 className="mb-8 text-center text-3xl bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          AI Trade Analyst
        </h1>

        {!pageReady ? (
          <p className="text-center text-gray-400">Loading…</p>
        ) : !pro ? (
          <div className="mx-auto max-w-lg rounded-xl border border-white/10 bg-black/30 p-6 text-center">
            <p className="mb-2 text-gray-400">
              AI Analyst is a Pro feature
            </p>
            <Link
              href="/settings"
              className="inline-block rounded bg-emerald-500 px-4 py-2 font-medium text-white hover:bg-emerald-600"
            >
              Upgrade to Pro
            </Link>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
            <div className="max-h-[80vh] overflow-y-auto rounded-xl border border-white/10 bg-white/5 p-4">
              {trades.map((trade) => (
                <div
                  key={trade.id}
                  onClick={() => void analyzeTrade(trade)}
                  className={`mb-3 cursor-pointer rounded border p-4 ${
                    selectedTrade?.id === trade.id
                      ? "border-emerald-400 bg-white/10"
                      : "border-white/10 hover:bg-white/10"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold">
                        {trade.ticker} • {trade.direction}
                      </p>

                      <p className="text-xs text-gray-400">
                        {formatDate(trade.created_at)} • {trade.session}
                      </p>

                      <p className="text-xs text-gray-500">
                        {trade.account_type} {trade.account_size}
                      </p>
                    </div>

                    <div className="text-right">
                      <p
                        className={
                          trade.pnl >= 0 ? "text-green-400" : "text-red-400"
                        }
                      >
                        {formatCurrency(trade.pnl)}
                      </p>

                      <p className="text-xs text-gray-400">
                        RR: {trade.rr ?? "-"}
                        {trade.contracts != null
                          ? ` • Contracts: ${trade.contracts}`
                          : ""}
                      </p>

                      {trade.ai_feedback && (
                        <p className="mt-1 text-xs text-emerald-400">Analyzed</p>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <div className="flex h-[80vh] flex-col rounded-xl border border-white/10 bg-white/5 p-4">
              {!selectedTrade && (
                <p className="mt-10 text-center text-gray-400">Select a trade</p>
              )}

              {selectedTrade && (
                <>
                  <div className="mb-4 space-y-1 text-sm">
                    <p className="text-lg font-semibold">
                      {selectedTrade.ticker} • {selectedTrade.direction}
                    </p>

                    <p
                      className={
                        selectedTrade.pnl >= 0
                          ? "text-green-400"
                          : "text-red-400"
                      }
                    >
                      {formatCurrency(selectedTrade.pnl)}
                    </p>

                    <p>
                      {formatDate(selectedTrade.created_at)} •{" "}
                      {selectedTrade.session}
                    </p>

                    <p className="text-gray-400">
                      {selectedTrade.account_type}{" "}
                      {selectedTrade.account_size} ({selectedTrade.account_id})
                    </p>

                    {selectedTrade.entry_price && (
                      <p>
                        Entry: {selectedTrade.entry_price} → Exit:{" "}
                        {selectedTrade.exit_price}
                      </p>
                    )}

                    {selectedTrade.contracts != null && (
                      <p>Contracts: {selectedTrade.contracts}</p>
                    )}

                    {selectedTrade.notes && (
                      <p className="italic text-gray-400">
                        {selectedTrade.notes}
                      </p>
                    )}
                  </div>

                  {selectedTrade.image_url && (
                    <img
                      src={`${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${selectedTrade.image_url}`}
                      className="mb-4 max-h-48 rounded border border-white/10 object-cover"
                      alt=""
                    />
                  )}

                  <div className="mb-4 flex-1 space-y-4 overflow-y-auto">
                    {messages.map((msg, i) => (
                      <div
                        key={i}
                        className={`max-w-[80%] rounded p-3 ${
                          msg.role === "user"
                            ? "ml-auto bg-blue-500"
                            : "bg-white/10"
                        }`}
                      >
                        <div className="whitespace-pre-wrap text-sm">
                          {msg.content}
                        </div>
                      </div>
                    ))}

                    {loading && <p className="text-gray-400">Analyzing...</p>}
                  </div>

                  <div className="flex gap-2">
                    <input
                      value={input}
                      onChange={(e) => setInput(e.target.value)}
                      placeholder="Ask about this trade..."
                      className="flex-1 rounded border border-white/10 bg-[#0f172a] p-2"
                    />

                    <button
                      type="button"
                      onClick={() => void sendMessage()}
                      className="rounded bg-emerald-500 px-4"
                    >
                      Send
                    </button>
                  </div>
                </>
              )}
            </div>
          </div>
        )}
      </div>
    </>
  )
}
