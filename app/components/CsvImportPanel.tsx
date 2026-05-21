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
import { ensureImportedCsvAccountRegistered } from "@/lib/ensureManualUserAccount"
import {
  type CsvSelectedAccount,
  insertCsvTradesWithAccount,
} from "@/lib/insertCsvTradesWithAccount"
import { last24hIso } from "@/lib/freePlanLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { useToast } from "@/app/components/ui"

export type CsvImportPanelProps = {
  /** Smaller preview + less chrome (e.g. onboarding modal) */
  compact?: boolean
  /** Called after trades are inserted successfully */
  onImportSuccess?: (info: { count: number; skipped: number }) => void
  /** Optional id so an external `<label htmlFor>` can trigger the file input */
  fileInputId?: string
  /**
   * When set, merged into each row before insert (same as `InputTradeForm` CSV import).
   * Use with `requireSelectedAccount` in onboarding.
   */
  selectedAccount?: CsvSelectedAccount | null
  /** If true, import is blocked until `selectedAccount` is set */
  requireSelectedAccount?: boolean
}

export default function CsvImportPanel({
  compact = false,
  onImportSuccess,
  fileInputId,
  selectedAccount = null,
  requireSelectedAccount = false,
}: CsvImportPanelProps) {
  const toast = useToast()
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

    if (requireSelectedAccount && !selectedAccount) {
      alert("Please create or select an account before importing trades")
      return
    }

    setLoading(true)

    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) {
      alert("Please log in first")
      setLoading(false)
      return
    }

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("is_pro, has_used_initial_import")
      .eq("id", user.id)
      .single()

    if (profileErr || !profile) {
      console.error("Profile fetch failed:", profileErr)
      alert("Could not verify account. Try again.")
      setLoading(false)
      return
    }

    const hasUsedInitialImport = profile.has_used_initial_import === true

    const { parsedTrades, summary, rowResults } = buildTradesFromParsedCsv(parsed, user.id)

    if (!parsedTrades.length) {
      alert(
        `Nothing to import: ${summary.failed} of ${summary.total} row(s) failed validation. Check console for details.`
      )
      setLoading(false)
      return
    }

    let tradesToInsert = parsedTrades
    if (!profile.is_pro) {
      if (!hasUsedInitialImport) {
        tradesToInsert = parsedTrades
      } else {
        const { data: existingTrades, error: existingErr } = await supabase
          .from("trades")
          .select("id")
          .eq("user_id", user.id)
          .gte("created_at", last24hIso())

        if (existingErr) {
          console.error("trade count check failed:", existingErr)
          alert("Could not verify daily trade limit. Please try again.")
          setLoading(false)
          return
        }

        const remaining = 3 - (existingTrades?.length ?? 0)
        if (remaining <= 0) {
          alert("You've reached your daily trade limit. Upgrade to Pro.")
          setLoading(false)
          return
        }
        tradesToInsert = parsedTrades.slice(0, remaining)
      }
    }

    if (!tradesToInsert.length) {
      alert("You've reached your daily trade limit. Upgrade to Pro.")
      setLoading(false)
      return
    }

    const isInitialImportOnRows = !hasUsedInitialImport

    let error: { message?: string; details?: string; hint?: string } | null = null

    if (selectedAccount) {
      const res = await insertCsvTradesWithAccount(
        supabase,
        tradesToInsert,
        selectedAccount,
        { isInitialImport: isInitialImportOnRows }
      )
      error = res.error
    } else {
      const rowsToInsert = tradesInsertRowsPrivate(tradesToInsert, {
        isInitialImport: isInitialImportOnRows,
      })

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

      const ins = await supabase.from("trades").insert(rowsToInsert)
      error = ins.error
    }

    if (error) {
      console.error("INSERT ERROR:", error)
      alert(handleSupabaseError(error))
    } else {
      if (!hasUsedInitialImport) {
        const { error: initialImportFlagErr } = await supabase
          .from("profiles")
          .update({ has_used_initial_import: true })
          .eq("id", user.id)
        if (initialImportFlagErr) {
          console.error("mark has_used_initial_import:", initialImportFlagErr)
        }
      }

      const skipped = summary.failed
      const errLines = rowResults
        .filter((r): r is { ok: false; rowNumber: number; reason: string } => !r.ok)
        .slice(0, 5)
        .map((r) => `Row ${r.rowNumber}: ${r.reason}`)
        .join("\n")
      const importedCount = tradesToInsert.length
      const partialCount = parsedTrades.length - tradesToInsert.length
      let msg = `Trades imported successfully. They are private by default. You can make them public by editing a trade. (${importedCount} imported)`
      if (partialCount > 0) {
        msg = `Imported ${importedCount} trades. Upgrade to Pro to import more.`
      }
      if (skipped) msg += ` ${skipped} row(s) skipped.`
      if (errLines) msg += `\n\n${errLines}`
      toast.success(msg, 6000)
      setParsed([])
      onImportSuccess?.({ count: importedCount, skipped })
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
          disabled={
            loading || (requireSelectedAccount && !selectedAccount)
          }
          className="w-full rounded-xl bg-emerald-500 px-4 py-2.5 font-semibold text-white transition hover:bg-emerald-600 disabled:opacity-60"
        >
          {loading ? "Importing..." : "Import trades"}
        </button>
      )}
    </div>
  )
}
