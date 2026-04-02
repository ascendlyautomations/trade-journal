"use client"

import { useState } from "react"
import Papa from "papaparse"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

export default function ImportPage() {
  const [loading, setLoading] = useState(false)

  async function handleCSVUpload(e: any) {
    const file = e.target.files[0]
    if (!file) return

    setLoading(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: async (results: any) => {
        try {
          const rows = results.data

          // 🔥 MAP CSV → YOUR TRADE STRUCTURE
          const formattedTrades = rows.map((row: any) => ({
            user_id: user?.id,
            ticker: row.Symbol || row.symbol || "",
            pnl: Number(row.PnL || row.pnl || 0),
            direction: row.Side || row.side || "Long",
            rr: Number(row.RR || row.rr || 0),
            points: Number(row.Points || row.points || 0),
            session: row.Session || "NY",
            account_type: row.Account || "Unknown",
            account_id: row.AccountID || "",
            notes: "",
            reviewed: false, // 🔥 KEY PART
            created_at: row.Date
              ? new Date(row.Date).toISOString()
              : new Date().toISOString(),
          }))

          // 🔥 BATCH INSERT (important)
          const chunkSize = 100

          for (let i = 0; i < formattedTrades.length; i += chunkSize) {
            const chunk = formattedTrades.slice(i, i + chunkSize)

            const { error } = await supabase
              .from("trades")
              .insert(chunk)

            if (error) {
              console.error(error)
              alert("Error uploading trades")
              setLoading(false)
              return
            }
          }

          alert(`Uploaded ${formattedTrades.length} trades 🚀`)
        } catch (err) {
          console.error(err)
          alert("CSV processing failed")
        }

        setLoading(false)
      },
    })
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">

        <div className="max-w-2xl mx-auto p-10">

          <h1 className="text-3xl font-bold mb-6 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Import Trades
          </h1>

          <div className="bg-white/5 backdrop-blur-md border border-white/10 rounded-xl p-8 text-center">

            <p className="text-gray-400 mb-6">
              Upload a CSV file from your broker to import trades instantly.
            </p>

            <input
              type="file"
              accept=".csv"
              onChange={handleCSVUpload}
              className="mb-4 block w-full text-sm text-gray-300"
            />

            {loading && (
              <p className="text-blue-400 mt-4">Uploading trades...</p>
            )}

          </div>

        </div>

      </div>
    </>
  )
}