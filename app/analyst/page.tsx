"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

export default function AnalystPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [selectedTrade, setSelectedTrade] = useState<any>(null)

  const [messages, setMessages] = useState<any[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    fetchTrades()
  }, [])

  async function fetchTrades() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    if (!user) return

    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })

    setTrades(data || [])
  }

  function formatCurrency(val: number) {
    if (val === null || val === undefined) return "-"
    return `${val < 0 ? "-" : ""}$${Math.abs(val).toLocaleString()}`
  }

  function formatDate(date: string) {
    return new Date(date).toLocaleDateString()
  }

  // 🔥 MAIN ANALYZE FUNCTION
  async function analyzeTrade(trade: any) {
    setSelectedTrade(trade)

    // ✅ IF ALREADY ANALYZED → LOAD INSTANTLY
    if (trade.ai_feedback) {
      setMessages([{ role: "assistant", content: trade.ai_feedback }])
      return
    }

    setMessages([])
    setLoading(true)

    const res = await fetch("/api/analyze-trade", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        trade,
        messages: []
      })
    })

    const data = await res.json()

    setMessages([{ role: "assistant", content: data.reply }])
    setLoading(false)
  }

  async function sendMessage() {
    if (!input.trim() || !selectedTrade) return

    const newMessages = [
      ...messages,
      { role: "user", content: input }
    ]

    setMessages(newMessages)
    setInput("")
    setLoading(true)

    const res = await fetch("/api/analyze-trade", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        trade: selectedTrade,
        messages: newMessages
      })
    })

    const data = await res.json()

    setMessages([
      ...newMessages,
      { role: "assistant", content: data.reply }
    ])

    setLoading(false)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-10">

        <h1 className="text-3xl text-center mb-8 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          AI Trade Analyst
        </h1>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

          {/* LEFT — TRADE LIST */}
          <div className="bg-white/5 border border-white/10 rounded-xl p-4 max-h-[80vh] overflow-y-auto">

            {trades.map((trade) => (
              <div
                key={trade.id}
                onClick={() => analyzeTrade(trade)}
                className={`p-4 mb-3 rounded cursor-pointer border ${
                  selectedTrade?.id === trade.id
                    ? "border-emerald-400 bg-white/10"
                    : "border-white/10 hover:bg-white/10"
                }`}
              >
                <div className="flex justify-between items-center">

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
                    <p className={trade.pnl >= 0 ? "text-green-400" : "text-red-400"}>
                      {formatCurrency(trade.pnl)}
                    </p>

                    <p className="text-xs text-gray-400">
                      RR: {trade.rr ?? "-"}
                      {trade.contracts != null ? ` • Contracts: ${trade.contracts}` : ""}
                    </p>

                    {trade.ai_feedback && (
                      <p className="text-xs text-emerald-400 mt-1">
                        Analyzed
                      </p>
                    )}
                  </div>

                </div>
              </div>
            ))}

          </div>

          {/* RIGHT — DETAILS + CHAT */}
          <div className="bg-white/5 border border-white/10 rounded-xl p-4 flex flex-col h-[80vh]">

            {!selectedTrade && (
              <p className="text-gray-400 text-center mt-10">
                Select a trade
              </p>
            )}

            {selectedTrade && (
              <>
                {/* 🔥 TRADE HEADER */}
                <div className="mb-4 text-sm space-y-1">

                  <p className="font-semibold text-lg">
                    {selectedTrade.ticker} • {selectedTrade.direction}
                  </p>

                  <p className={selectedTrade.pnl >= 0 ? "text-green-400" : "text-red-400"}>
                    {formatCurrency(selectedTrade.pnl)}
                  </p>

                  <p>
                    {formatDate(selectedTrade.created_at)} • {selectedTrade.session}
                  </p>

                  <p className="text-gray-400">
                    {selectedTrade.account_type} {selectedTrade.account_size} ({selectedTrade.account_id})
                  </p>

                  {selectedTrade.entry_price && (
                    <p>
                      Entry: {selectedTrade.entry_price} → Exit: {selectedTrade.exit_price}
                    </p>
                  )}

                  {selectedTrade.contracts != null && (
                    <p>Contracts: {selectedTrade.contracts}</p>
                  )}

                  {selectedTrade.notes && (
                    <p className="text-gray-400 italic">
                      {selectedTrade.notes}
                    </p>
                  )}

                </div>

                {/* 🔥 IMAGE */}
                {selectedTrade.image_url && (
                  <img
                    src={`${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${selectedTrade.image_url}`}
                    className="rounded mb-4 border border-white/10 max-h-48 object-cover"
                  />
                )}

                {/* 🔥 CHAT */}
                <div className="flex-1 overflow-y-auto space-y-4 mb-4">

                  {messages.map((msg, i) => (
                    <div
                      key={i}
                      className={`p-3 rounded max-w-[80%] ${
                        msg.role === "user"
                          ? "bg-blue-500 ml-auto"
                          : "bg-white/10"
                      }`}
                    >
                      <div className="whitespace-pre-wrap text-sm">
                        {msg.content}
                      </div>
                    </div>
                  ))}

                  {loading && (
                    <p className="text-gray-400">Analyzing...</p>
                  )}

                </div>

                {/* INPUT */}
                <div className="flex gap-2">
                  <input
                    value={input}
                    onChange={(e) => setInput(e.target.value)}
                    placeholder="Ask about this trade..."
                    className="flex-1 p-2 rounded bg-[#0f172a] border border-white/10"
                  />

                  <button
                    onClick={sendMessage}
                    className="bg-emerald-500 px-4 rounded"
                  >
                    Send
                  </button>
                </div>

              </>
            )}

          </div>

        </div>

      </div>
    </>
  )
}