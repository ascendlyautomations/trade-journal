"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"
import { useRouter } from "next/navigation"


export default function ReviewPage() {
  const [trades, setTrades] = useState<any[]>([])
  const [index, setIndex] = useState(0)
  const [notes, setNotes] = useState("")
  const [loading, setLoading] = useState(true)

  const router = useRouter()

  useEffect(() => {
    fetchTrades()
  }, [])

  async function fetchTrades() {
    const {
      data: { user }
    } = await supabase.auth.getUser()

    const { data } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", user?.id)
      .eq("reviewed", false)
      .order("created_at", { ascending: true })

    setTrades(data || [])
    setLoading(false)
  }

  const trade = trades[index]

  async function handleSave() {
    if (!trade) return

    await supabase
      .from("trades")
      .update({
        notes,
        reviewed: true
      })
      .eq("id", trade.id)

    setNotes("")
    setIndex((prev) => prev + 1)
  }

  async function handleSaveAndExit() {
  if (!trade) return

  await supabase
    .from("trades")
    .update({
      notes,
      reviewed: true
    })
    .eq("id", trade.id)

  router.push("/app") // ✅ THIS is your input trade page
}

  if (loading) {
    return (
      <div className="text-white p-10">Loading trades...</div>
    )
  }

  if (!trade) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          <h1 className="text-2xl font-bold">
            No trades left to review 🎉
          </h1>
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">

        <div className="max-w-4xl mx-auto p-10">

          <h1 className="text-2xl mb-6 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent font-bold">
            Review Trade {index + 1} of {trades.length}
          </h1>

          <div className="bg-white/5 backdrop-blur-md border border-white/10 rounded-xl p-6 space-y-4">

            {/* Trade Info */}
            <div className="flex justify-between">
              <p><b>{trade.ticker}</b></p>
              <p className={trade.pnl > 0 ? "text-emerald-400" : "text-red-400"}>
                ${trade.pnl}
              </p>
            </div>

            <p className="text-gray-400 text-sm">
              {new Date(trade.created_at).toLocaleDateString()}
            </p>

            {/* Notes */}
            <textarea
              placeholder="What did you see here? (confluences, mistakes, etc.)"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full p-3 bg-[#0f172a] border border-white/10 rounded text-white"
            />

            {/* Buttons */}
            <div className="flex gap-3 mt-4">
              {/* Save & Exit */}
              <button
                onClick={handleSaveAndExit}
                className="flex-1 bg-red-500 hover:bg-red-600 py-3 rounded font-semibold transition"
              >
                Save & Exit
              </button>
              
              {/* Save & Next */}
              <button
                onClick={handleSave}
                className="flex-1 bg-emerald-500 hover:bg-emerald-600 py-3 rounded font-semibold transition"
              >
                Save & Next →
              </button>

              

            </div>

          </div>

        </div>

      </div>
    </>
  )
}