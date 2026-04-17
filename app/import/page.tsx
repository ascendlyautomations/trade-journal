"use client"

import { useState } from "react"
import Papa from "papaparse"
import { supabase } from "@/lib/supabaseClient"
import {
  type CsvRow,
  buildTradesFromParsedCsv,
  isTradovateCsvRow,
  mapCsvHeadersToFields,
  stripBom,
} from "@/lib/csvTradeParsers"
import Navbar from "../components/Navbar"

export default function ImportPage() {
  const [parsed, setParsed] = useState<CsvRow[]>([])
  const [loading, setLoading] = useState(false)

  const handleFile = (file: File) => {
    Papa.parse<CsvRow>(file, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h: string) => stripBom(String(h).trim()),
      complete: (results) => {
        const data = (results.data || []) as CsvRow[]
        const filtered = data.filter(
          (r) => r && typeof r === "object" && Object.keys(r).length > 0
        )
        setParsed(filtered)
      },
    })
  }

  const handleImport = async () => {
    console.log("🚨 INSERT FUNCTION HIT 🚨", "app/import/page.tsx handleImport")

    if (parsed.length === 0) return
    setLoading(true)

    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) {
      alert("Please log in first")
      setLoading(false)
      return
    }

    const { isTradovate, parsedTrades, summary, rowResults } = buildTradesFromParsedCsv(
      parsed,
      user.id
    )
    console.log("TRADOVATE DETECTED:", isTradovate)
    console.log("CSV import summary:", summary)
    console.log("PARSED TRADES:", parsedTrades)
    if (parsedTrades.length) {
      console.debug(
        "CSV duration debug (first 5):",
        parsedTrades.slice(0, 5).map((t) => ({
          ticker: t.ticker,
          duration_text: t.duration_text,
          duration_seconds: t.duration_seconds,
        }))
      )
    }

    if (!parsedTrades.length) {
      alert(
        `Nothing to import: ${summary.failed} of ${summary.total} row(s) failed validation. Check console for details.`
      )
      setLoading(false)
      return
    }

    const { data, error } = await supabase
      .from("trades")
      .insert(parsedTrades)
      .select()

    console.log("🚨 INSERT RESULT:", data)
    console.log("🚨 INSERT ERROR:", error)

    if (error) {
      console.error("INSERT ERROR:", error)
      alert("Import failed")
    } else {
      const skipped = summary.failed
      const errLines = rowResults
        .filter((r): r is { ok: false; rowNumber: number; reason: string } => !r.ok)
        .slice(0, 5)
        .map((r) => `Row ${r.rowNumber}: ${r.reason}`)
        .join("\n")
      let msg = `Imported ${parsedTrades.length} trade(s).`
      if (skipped) msg += ` ${skipped} row(s) skipped.`
      if (errLines) msg += `\n\n${errLines}`
      alert(msg)
      setParsed([])
    }

    setLoading(false)
  }

  const isTradovateFormat =
    parsed.length > 0 && isTradovateCsvRow(parsed[0])

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-[#0f172a] text-white p-6">
        <div className="max-w-4xl mx-auto">
          <h1 className="text-2xl mb-4">Import Trades</h1>

          <input
            type="file"
            accept=".csv"
            onChange={(e) => {
              const file = e.target.files?.[0]
              if (file) handleFile(file)
            }}
            className="mb-4 block w-full text-sm text-gray-300"
          />

          {parsed.length > 0 ? (
            <p className="mb-3 text-xs text-gray-400">
              Parsed {parsed.length} rows from CSV
              {isTradovateFormat ? " (Tradovate)" : ""}
            </p>
          ) : null}
          <p className="text-sm text-gray-400 mb-2">
            Tradovate raw exports (buyPrice / sellPrice) or flexible broker CSV: headers like
            Date / Trade Date, Symbol / Ticker, Direction / Side, PnL / Realized P&L, optional
            entry/exit, contracts, session, account fields. Row errors are skipped; valid rows
            import.
          </p>

          {parsed.length > 0 && (
            <>
              <pre className="text-xs bg-black p-2 mb-4 overflow-auto max-h-40">
                {JSON.stringify(parsed[0], null, 2)}
              </pre>
              <div className="overflow-x-auto mb-4 rounded-lg border border-white/10 bg-[#111827]">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-gray-400">
                      <th className="p-2 text-left">Date</th>
                      <th className="p-2 text-left">Ticker</th>
                      <th className="p-2 text-left">Direction</th>
                      <th className="p-2 text-left">PnL</th>
                    </tr>
                  </thead>
                  <tbody>
                    {parsed.slice(0, 10).map((t, i) => {
                      const mapped = isTradovateFormat ? null : mapCsvHeadersToFields(t)
                      return (
                      <tr key={i} className="border-t border-white/10">
                        <td className="p-2">
                          {isTradovateFormat
                            ? t["boughtTimestamp"] || "-"
                            : mapped?.date || "—"}
                        </td>
                        <td className="p-2">
                          {isTradovateFormat
                            ? t["symbol"] || "-"
                            : mapped?.symbol || "—"}
                        </td>
                        <td className="p-2">
                          {isTradovateFormat
                            ? Number(t["sellPrice"]) > Number(t["buyPrice"])
                              ? "Long"
                              : "Short"
                            : mapped?.direction || "—"}
                        </td>
                        <td className="p-2">
                          {isTradovateFormat ? (t["pnl"] ?? "-") : mapped?.pnl ?? "—"}
                        </td>
                      </tr>
                    )})}
                  </tbody>
                </table>
              </div>

              <button
                onClick={() => void handleImport()}
                disabled={loading}
                className="bg-green-500 px-4 py-2 rounded disabled:opacity-60"
              >
                {loading ? "Importing..." : "Import Trades"}
              </button>
            </>
          )}
        </div>
      </div>
    </>
  )
}
