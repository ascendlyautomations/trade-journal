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
        <div className="p-6 max-w-8xl mx-auto">
          <h1 className="mb-2 text-center text-xl md:text-2xl font-semibold text-blue-300">
            Input Trade
          </h1>

          <input
            ref={csvInputRef}
            type="file"
            accept=".csv"
            className="hidden"
            onChange={handleCSVUpload}
          />

          <InputTradeForm
            onUploadCsvClick={() => csvInputRef.current?.click()}
            onReviewCsvClick={() => {
              window.location.href = "/review"
            }}
            reviewCount={reviewCount}
            csvLoading={loading}
          />
        </div>
      </div>
    </>
  )
}
