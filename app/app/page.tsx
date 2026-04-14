"use client"

import Navbar from "../components/Navbar"
import InputTradeForm from "../components/InputTradeForm"
import { useState, useRef, useEffect } from "react"
import Papa from "papaparse"
import { supabase } from "../../lib/supabaseClient"
import { buildTradesFromParsedCsv } from "@/lib/csvTradeParsers"

export default function Home() {
  const [loading, setLoading] = useState(false)
  const [reviewCount, setReviewCount] = useState(0)

  const csvInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    fetchReviewCount()
  }, [])

  async function handleCSVUpload(e: any) {
    const file = e.target.files[0]
    if (!file) return

    setLoading(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user?.id) {
      alert("Please log in first")
      setLoading(false)
      return
    }

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: async (results: any) => {
        try {
          const rows = (results.data || []).filter(
            (r: any) => r && typeof r === "object" && Object.keys(r).length > 0
          )
          if (!rows.length) {
            alert("No rows to import")
            setLoading(false)
            return
          }

          const { isTradovate, parsedTrades: tradesToInsert } =
            buildTradesFromParsedCsv(rows, user.id)

          console.log("TRADOVATE DETECTED:", isTradovate)
          console.log("PARSED TRADES:", tradesToInsert)
          console.log("✅ FINAL INSERT PAYLOAD:", tradesToInsert)

          const chunkSize = 100

          for (let i = 0; i < tradesToInsert.length; i += chunkSize) {
            const chunk = tradesToInsert.slice(i, i + chunkSize)

            const { error } = await supabase.from("trades").insert(chunk)

            if (error) {
              console.error(error)
              alert("Error uploading trades")
              setLoading(false)
              return
            }
          }

          alert(`Uploaded ${tradesToInsert.length} trades 🚀`)
          fetchReviewCount()
        } catch (err) {
          console.error(err)
          alert("CSV processing failed")
        }

        setLoading(false)
      },
    })
  }

  async function fetchReviewCount() {
    const {
      data: { user },
    } = await supabase.auth.getUser()

    const { count } = await supabase
      .from("trades")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user?.id)
      .eq("reviewed", false)

    setReviewCount(count || 0)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="p-8 max-w-7xl mx-auto">
          <h1 className="text-3xl font-semibold mb-2 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Input Trade
          </h1>

          <div className="flex items-center justify-between mb- flex-wrap gap-4">
            <div className="w-full flex items-center mb-6">
              <div className="flex gap-2">
                <button
                  onClick={() => csvInputRef.current?.click()}
                  className="bg-blue-500 px-4 py-2 rounded disabled:opacity-60"
                  disabled={loading}
                  type="button"
                >
                  Upload CSV
                </button>

                <button
                  onClick={() => (window.location.href = "/review")}
                  className="relative bg-emerald-500 px-4 py-2 rounded"
                  type="button"
                >
                  Review CSV Inputs
                  {reviewCount > 0 && (
                    <span className="absolute -top-2 -right-2 bg-red-500 text-white text-xs px-2 py-0.5 rounded-full">
                      {reviewCount > 99 ? "99+" : reviewCount}
                    </span>
                  )}
                </button>
              </div>
            </div>
          </div>

          <input
            ref={csvInputRef}
            type="file"
            accept=".csv"
            className="hidden"
            onChange={handleCSVUpload}
          />

          <InputTradeForm />
        </div>
      </div>
    </>
  )
}
