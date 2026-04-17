"use client"

import Navbar from "../components/Navbar"
import InputTradeForm from "../components/InputTradeForm"
import { useState, useRef, useEffect } from "react"
import Papa from "papaparse"
import { supabase } from "../../lib/supabaseClient"
import {
  buildTradesFromParsedCsv,
  stripBom,
} from "@/lib/csvTradeParsers"

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
      transformHeader: (h: string) => stripBom(String(h).trim()),
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

          const { isTradovate, parsedTrades: tradesToInsert, summary, rowResults } =
            buildTradesFromParsedCsv(rows, user.id)

          console.log("TRADOVATE DETECTED:", isTradovate)
          console.log("CSV import summary:", summary)
          console.log("PARSED TRADES:", tradesToInsert)
          if (tradesToInsert.length) {
            console.debug(
              "CSV duration debug (first 5):",
              tradesToInsert.slice(0, 5).map((t) => ({
                ticker: t.ticker,
                duration_text: t.duration_text,
                duration_seconds: t.duration_seconds,
              }))
            )
          }
          if (rowResults?.length) {
            const bad = rowResults.filter((r) => !r.ok)
            if (bad.length) console.warn("CSV row issues:", bad)
          }

          if (!tradesToInsert.length) {
            alert(
              `No valid rows to import. ${summary.total} row(s) scanned, ${summary.failed} failed. Check the console for details.`
            )
            setLoading(false)
            return
          }

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

          const skipped = summary.failed
          const errLines = (rowResults || [])
            .filter((r): r is { ok: false; rowNumber: number; reason: string } => !r.ok)
            .slice(0, 6)
            .map((r) => `Row ${r.rowNumber}: ${r.reason}`)
            .join("\n")

          let msg = `Uploaded ${tradesToInsert.length} trade(s).`
          if (summary.total > tradesToInsert.length) {
            msg += ` ${skipped} row(s) skipped (${summary.total} total).`
          }
          if (errLines) {
            msg += `\n\n${errLines}${skipped > 6 ? "\n…" : ""}`
          }
          alert(msg)
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
      .in("account_type", ["imported", "Imported"])
      .eq("reviewed", false)

    setReviewCount(count || 0)
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="pt-3 px-6 pb-6 max-w-8xl mx-auto">
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
