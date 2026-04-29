"use client"

import Navbar from "../components/Navbar"
import InputTradeForm from "../components/InputTradeForm"
import { useState, useRef, useEffect } from "react"
import Papa from "papaparse"
import { supabase } from "../../lib/supabaseClient"
import { buildTradesFromParsedCsv, stripBom } from "@/lib/csvTradeParsers"
import {
  INPUT_TRADE_PAGE_TITLE_CLASSNAME,
  INPUT_TRADE_PAGE_TITLE_ROW_CLASSNAME,
} from "@/lib/inputTradePageTitle"

export default function Home() {
  const [loading, setLoading] = useState(false)
  const [reviewCount, setReviewCount] = useState(0)
  const [parsedTrades, setParsedTrades] = useState<any[]>([])

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

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("is_pro, has_used_csv_import")
      .eq("id", user.id)
      .single()

    if (profileErr || !profile) {
      console.error("Profile fetch failed:", profileErr)
      alert("Could not verify account. Try again.")
      setLoading(false)
      return
    }

    console.log("CSV CHECK:", profile)

    if (!profile.is_pro && profile.has_used_csv_import) {
      alert("Free plan includes one CSV import only. Upgrade to import more.")
      setLoading(false)
      return
    }

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h: string) => stripBom(String(h).trim()),
      complete: (results: any) => {
        const parsed = buildTradesFromParsedCsv(results.data, user.id)

        setParsedTrades(parsed.parsedTrades)

        console.log("SET PARSED TRADES:", parsed.parsedTrades.length)

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
          <div className={INPUT_TRADE_PAGE_TITLE_ROW_CLASSNAME}>
            <h1 className={INPUT_TRADE_PAGE_TITLE_CLASSNAME}>Input Trade</h1>
          </div>

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
            parsedTrades={parsedTrades}
            onParsedTradesClear={() => {
              setParsedTrades([])
              fetchReviewCount()
            }}
          />
        </div>
      </div>
    </>
  )
}
