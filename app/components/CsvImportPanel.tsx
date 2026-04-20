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
  tradesInsertRowsPrivate,
} from "@/lib/csvTradeParsers"
import { assertCsvImportAllowedForFreePlan, markProfileCsvImportUsed } from "@/lib/csvImportGate"
import { ensureImportedCsvAccountRegistered } from "@/lib/ensureManualUserAccount"

export type CsvImportPanelProps = {
  /** Smaller preview + less chrome (e.g. onboarding modal) */
  compact?: boolean
  /** Called after trades are inserted successfully */
  onImportSuccess?: (info: { count: number; skipped: number }) => void
  /** Optional id so an external `<label htmlFor>` can trigger the file input */
  fileInputId?: string
}

export default function CsvImportPanel({
  compact = false,
  onImportSuccess,
  fileInputId,
}: CsvImportPanelProps) {
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
    if (parsed.length === 0) return
    setLoading(true)

    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) {
      alert("Please log in first")
      setLoading(false)
      return
    }

    const gate = await assertCsvImportAllowedForFreePlan(supabase, user.id)
    if (!gate.ok) {
      alert(
        "Free plan allows one CSV import only. Upgrade for unlimited imports."
      )
      setLoading(false)
      return
    }

    const { parsedTrades, summary, rowResults } = buildTradesFromParsedCsv(parsed, user.id)

    if (!parsedTrades.length) {
      alert(
        `Nothing to import: ${summary.failed} of ${summary.total} row(s) failed validation. Check console for details.`
      )
      setLoading(false)
      return
    }

    const rowsToInsert = tradesInsertRowsPrivate(parsedTrades)

    const { error: importAcctErr } = await ensureImportedCsvAccountRegistered(
      supabase,
      user.id
    )
    if (importAcctErr) {
      console.error(importAcctErr)
      alert("Could not register imported account row. Try again.")
      setLoading(false)
      return
    }

    const { error } = await supabase.from("trades").insert(rowsToInsert).select()

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
      let msg = `Trades imported successfully. They are private by default. You can make them public by editing a trade. (${parsedTrades.length} imported)`
      if (skipped) msg += ` ${skipped} row(s) skipped.`
      if (errLines) msg += `\n\n${errLines}`
      alert(msg)
      setParsed([])
      const { error: flagErr } = await markProfileCsvImportUsed(supabase, user.id)
      if (flagErr) console.error("markProfileCsvImportUsed:", flagErr)
      onImportSuccess?.({ count: parsedTrades.length, skipped })
    }

    setLoading(false)
  }

  const isTradovateFormat = parsed.length > 0 && isTradovateCsvRow(parsed[0])

  return (
    <div className={compact ? "space-y-3" : "space-y-4"}>
      <input
        id={fileInputId}
        type="file"
        accept=".csv"
        onChange={(e) => {
          const file = e.target.files?.[0]
          if (file) handleFile(file)
        }}
        className="block w-full text-sm text-gray-300 file:mr-3 file:rounded-lg file:border-0 file:bg-emerald-500/20 file:px-3 file:py-1.5 file:text-sm file:text-emerald-200"
      />

      {parsed.length > 0 ? (
        <p className="text-xs text-gray-400">
          Parsed {parsed.length} rows from CSV
          {isTradovateFormat ? " (Tradovate)" : ""}
        </p>
      ) : null}

      {!compact ? (
        <p className="text-sm text-gray-400">
          Tradovate raw exports (buyPrice / sellPrice) or flexible broker CSV: headers like Date /
          Trade Date, Symbol / Ticker, Direction / Side, PnL / Realized P&L, optional entry/exit,
          contracts, session, account fields.
        </p>
      ) : (
        <p className="text-xs text-gray-500">
          Tradovate exports or flexible CSV with date, symbol, side, and P&amp;L columns.
        </p>
      )}

      {parsed.length > 0 && !compact ? (
        <pre className="max-h-40 overflow-auto bg-black/40 p-2 text-xs">
          {JSON.stringify(parsed[0], null, 2)}
        </pre>
      ) : null}

      {parsed.length > 0 && (
        <div
          className={`overflow-x-auto rounded-lg border border-white/10 bg-[#111827]/80 ${compact ? "max-h-28" : "max-h-40"}`}
        >
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
              {parsed.slice(0, compact ? 5 : 10).map((t, i) => {
                const mapped = isTradovateFormat ? null : mapCsvHeadersToFields(t)
                return (
                  <tr key={i} className="border-t border-white/10">
                    <td className="p-2">
                      {isTradovateFormat ? t["boughtTimestamp"] || "-" : mapped?.date || "—"}
                    </td>
                    <td className="p-2">
                      {isTradovateFormat ? t["symbol"] || "-" : mapped?.symbol || "—"}
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
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {parsed.length > 0 && (
        <button
          type="button"
          onClick={() => void handleImport()}
          disabled={loading}
          className="w-full rounded-xl bg-emerald-500 px-4 py-2.5 font-semibold text-white transition hover:bg-emerald-600 disabled:opacity-60"
        >
          {loading ? "Importing..." : "Import trades"}
        </button>
      )}
    </div>
  )
}
