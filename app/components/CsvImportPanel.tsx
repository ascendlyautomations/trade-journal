"use client"

import { useRef, useState } from "react"
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
import { assessFreePlanTradeUpload } from "@/lib/freePlanLimits"
import { feedbackPresets, persistentSuccess } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import CsvImportUnsupportedBanner from "@/app/components/CsvImportUnsupportedBanner"
import CsvImportFailureModal from "@/app/components/CsvImportFailureModal"
import {
  detectCsvBrokerHint,
  isCsvFormatUnrecognized,
} from "@/lib/csvBrokerHint"
import {
  buildCsvImportDiagnostics,
  type CsvImportDiagnostics,
} from "@/lib/csvImportDiagnostics"
import CsvImportDiagnosticsPanel from "@/app/components/CsvImportDiagnosticsPanel"
import { buildCsvSupportNotes } from "@/lib/csvImportSupportNotes"
import { submitCsvSupportRequest } from "@/lib/submitCsvSupportRequest"
import { mirrorAccountSettingsHasUsedInitialImport } from "@/lib/profileSplitMirrorWrites"
import { csvTradesHaveFutureDate } from "@/lib/tradeDateValidation"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { notifyAdminCsvImportCompleted } from "@/lib/notifyAdminCsvImportCompleted"

export type CsvImportPanelProps = {
  /** Smaller preview + less chrome (e.g. onboarding modal) */
  compact?: boolean
  /** Called after trades are inserted successfully */
  onImportSuccess?: (info: {
    count: number
    skipped: number
    errorSummary?: string
  }) => void
  /**
   * When true, parent handles success feedback (e.g. onboarding modal that closes on complete).
   * Errors still show via this panel's FeedbackModal.
   */
  delegateSuccessFeedback?: boolean
  /** Optional id so an external `<label htmlFor>` can trigger the file input */
  fileInputId?: string
  /**
   * When set, merged into each row before insert (same as `InputTradeForm` CSV import).
   * Use with `requireSelectedAccount` in onboarding.
   */
  selectedAccount?: CsvSelectedAccount | null
  /** If true, import is blocked until `selectedAccount` is set */
  requireSelectedAccount?: boolean
  /** Label stored in csv_support_requests notes when user submits a failed file */
  importSource?: string
}

export default function CsvImportPanel({
  compact = false,
  onImportSuccess,
  delegateSuccessFeedback = false,
  fileInputId,
  selectedAccount = null,
  requireSelectedAccount = false,
  importSource = "csv_import_panel",
}: CsvImportPanelProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [parsed, setParsed] = useState<CsvRow[]>([])
  const [loading, setLoading] = useState(false)
  const [unrecognized, setUnrecognized] = useState(false)
  const [brokerHint, setBrokerHint] = useState<string | null>(null)
  const [diagnostics, setDiagnostics] = useState<CsvImportDiagnostics | null>(null)
  const [csvSupportFile, setCsvSupportFile] = useState<File | null>(null)
  const [failureModalOpen, setFailureModalOpen] = useState(false)
  const [failureReason, setFailureReason] = useState("")
  const [submittingSupport, setSubmittingSupport] = useState(false)
  const importingRef = useRef(false)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const lastCsvFileRef = useRef<File | null>(null)

  function endImport() {
    importingRef.current = false
    setLoading(false)
  }

  function resetFileInput() {
    if (fileInputRef.current) fileInputRef.current.value = ""
  }

  function clearCsvState() {
    setParsed([])
    setUnrecognized(false)
    setBrokerHint(null)
    setDiagnostics(null)
    setCsvSupportFile(null)
    lastCsvFileRef.current = null
    resetFileInput()
  }

  function openFailureModal(reason: string) {
    setFailureReason(reason)
    setFailureModalOpen(true)
  }

  function applyParsePreview(rows: CsvRow[]) {
    const hint = detectCsvBrokerHint(rows)
    setBrokerHint(hint)
    const preview = buildTradesFromParsedCsv(
      rows,
      "00000000-0000-0000-0000-000000000000"
    )
    const diag = buildCsvImportDiagnostics(rows, preview)
    setUnrecognized(isCsvFormatUnrecognized(preview.summary))
    setDiagnostics(diag)
    return { preview, hint, diag }
  }

  function showParseFailure(
    reason: string,
    rows: CsvRow[] = [],
    preview?: ReturnType<typeof buildTradesFromParsedCsv>
  ) {
    if (rows.length > 0 && preview) {
      setParsed(rows)
      setBrokerHint(detectCsvBrokerHint(rows))
      setUnrecognized(isCsvFormatUnrecognized(preview.summary))
      setDiagnostics(buildCsvImportDiagnostics(rows, preview))
    } else {
      setParsed([])
      setUnrecognized(false)
      setBrokerHint(null)
      setDiagnostics(null)
    }
    openFailureModal(reason)
  }

  async function handleFile(file: File) {
    lastCsvFileRef.current = file
    setCsvSupportFile(file)
    setFailureModalOpen(false)

    if (file.size === 0) {
      clearCsvState()
      lastCsvFileRef.current = file
      openFailureModal("The file is empty.")
      return
    }

    let text: string
    try {
      text = await file.text()
    } catch {
      clearCsvState()
      lastCsvFileRef.current = file
      openFailureModal("Could not read the file.")
      return
    }

    if (text.trim() === "undefined") {
      clearCsvState()
      lastCsvFileRef.current = file
      openFailureModal('File content is invalid ("undefined").')
      return
    }

    Papa.parse<CsvRow>(file, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h: string) => stripBom(String(h).trim()),
      error: (err) => {
        clearCsvState()
        lastCsvFileRef.current = file
        openFailureModal(err.message || "Could not parse CSV file.")
      },
      complete: (results) => {
        const fields = (results.meta.fields ?? []).map((f) => stripBom(String(f).trim()))
        const hasHeaders = fields.some((f) => f.length > 0)

        const data = (results.data || []) as CsvRow[]
        const filtered = data.filter(
          (r) => r && typeof r === "object" && Object.keys(r).length > 0
        )

        if (!hasHeaders) {
          showParseFailure("No column headers found in CSV.", filtered)
          lastCsvFileRef.current = file
          return
        }

        if (filtered.length === 0) {
          showParseFailure("No data rows found in CSV.")
          lastCsvFileRef.current = file
          return
        }

        setParsed(filtered)
        const { preview } = applyParsePreview(filtered)

        if (isCsvFormatUnrecognized(preview.summary)) {
          openFailureModal("Unsupported CSV format — no rows could be imported.")
        }
      },
    })
  }

  async function handleSubmitCsvSupport() {
    const file = lastCsvFileRef.current
    if (!file) {
      showPopup(feedbackPresets.importFailed("No CSV file available to submit."))
      return
    }

    setSubmittingSupport(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      showPopup(feedbackPresets.importFailed("Please log in first."))
      setSubmittingSupport(false)
      return
    }

    const notes = buildCsvSupportNotes({
      failureReason,
      diagnostics,
      source: importSource,
      originalFilename: file.name,
    })

    const result = await submitCsvSupportRequest(supabase, {
      csvFile: file,
      brokerName: brokerHint ?? "Unknown",
      notes,
    })

    setSubmittingSupport(false)

    if (!result.ok) {
      showPopup(feedbackPresets.importFailed(result.message))
      return
    }

    setFailureModalOpen(false)
    clearCsvState()
    showPopup(
      persistentSuccess(
        "CSV submitted",
        "We'll review this format and work on adding support."
      )
    )
  }

  function handleTryAnotherFile() {
    resetFileInput()
    lastCsvFileRef.current = null
    setParsed([])
    setUnrecognized(false)
    setBrokerHint(null)
    setDiagnostics(null)
    fileInputRef.current?.click()
    setFailureModalOpen(false)
  }

  function handleFailureCancel() {
    setFailureModalOpen(false)
    clearCsvState()
  }

  const handleImport = async () => {
    if (parsed.length === 0) return
    if (importingRef.current || loading) return

    if (requireSelectedAccount && !selectedAccount) {
      showPopup(
        feedbackPresets.importFailed(
          "Please create or select an account before importing trades."
        )
      )
      return
    }

    importingRef.current = true
    setLoading(true)

    const importBatchId = crypto.randomUUID()

    const { data: userData } = await supabase.auth.getUser()
    const user = userData.user
    if (!user) {
      showPopup(feedbackPresets.importFailed("Please log in first."))
      endImport()
      return
    }

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("is_pro, has_used_initial_import")
      .eq("id", user.id)
      .single()

    if (profileErr || !profile) {
      console.error("Profile fetch failed:", profileErr)
      showPopup(feedbackPresets.importFailed("Could not verify account. Try again."))
      endImport()
      return
    }

    const hasUsedInitialImport = profile.has_used_initial_import === true

    const parseResult = buildTradesFromParsedCsv(parsed, user.id)
    const { parsedTrades, summary, rowResults } = parseResult

    if (!parsedTrades.length) {
      setUnrecognized(isCsvFormatUnrecognized(summary))
      setBrokerHint(detectCsvBrokerHint(parsed))
      setDiagnostics(buildCsvImportDiagnostics(parsed, parseResult))
      openFailureModal("No trades could be imported from this CSV.")
      endImport()
      return
    }

    if (csvTradesHaveFutureDate(parsedTrades)) {
      showPopup(feedbackPresets.csvImportFutureTradeDate())
      endImport()
      return
    }

    setUnrecognized(false)
    if (summary.failed > 0) {
      setDiagnostics(buildCsvImportDiagnostics(parsed, parseResult))
    } else {
      setDiagnostics(null)
    }

    let tradesToInsert = parsedTrades
    if (!profile.is_pro) {
      let uploadCheck
      try {
        uploadCheck = await assessFreePlanTradeUpload(
          supabase,
          user.id,
          parsedTrades.length
        )
      } catch {
        showPopup(feedbackPresets.importVerifyFailed())
        endImport()
        return
      }

      if (!uploadCheck.allowed) {
        showPopup(
          feedbackPresets.csvImportLimitExceeded(
            parsedTrades.length,
            uploadCheck.remaining
          )
        )
        endImport()
        return
      }

      tradesToInsert = parsedTrades
    }

    if (!tradesToInsert.length) {
      showPopup(feedbackPresets.tradeLimitReached())
      endImport()
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
        showPopup(
          feedbackPresets.importFailed(
            "Could not register imported account row. Try again."
          )
        )
        endImport()
        return
      }

      const ins = await supabase.from("trades").insert(rowsToInsert)
      error = ins.error
    }

    if (error) {
      console.error("INSERT ERROR:", error)
      showPopup(feedbackPresets.importFailed(handleSupabaseError(error)))
    } else {
      if (!hasUsedInitialImport) {
        const { error: initialImportFlagErr } = await supabase
          .from("profiles")
          .update({ has_used_initial_import: true })
          .eq("id", user.id)
        if (initialImportFlagErr) {
          console.error("mark has_used_initial_import:", initialImportFlagErr)
        } else {
          const { error: mirrorErr } = await mirrorAccountSettingsHasUsedInitialImport(
            supabase,
            user.id,
            true
          )
          if (mirrorErr) {
            console.error("mirror account_settings.has_used_initial_import:", mirrorErr)
          }
        }
      }

      const skipped = summary.failed
      const errLines = rowResults
        .filter((r): r is { ok: false; rowNumber: number; reason: string } => !r.ok)
        .slice(0, 5)
        .map((r) => `Row ${r.rowNumber}: ${r.reason}`)
        .join("\n")
      const importedCount = tradesToInsert.length
      const successFeedback = feedbackPresets.importSuccess(importedCount, skipped)
      let message = successFeedback.message as string
      if (errLines) message += `\n\n${errLines}`

      notifyAdminCsvImportCompleted({
        importBatchId,
        originalFilename:
          csvSupportFile?.name ?? lastCsvFileRef.current?.name ?? null,
        brokerFormat: brokerHint ?? diagnostics?.formatLabel ?? null,
        rowsParsed: parsed.length,
        tradesImported: importedCount,
        rowsSkipped: skipped > 0 ? skipped : undefined,
        accountName:
          selectedAccount?.name ??
          (parsedTrades[0]?.account_name != null
            ? String(parsedTrades[0].account_name)
            : null),
        accountId:
          selectedAccount?.id ??
          (parsedTrades[0]?.account_id != null
            ? String(parsedTrades[0].account_id)
            : null),
        source: importSource,
      })

      if (!delegateSuccessFeedback) {
        showPopup({ ...successFeedback, message })
      }

      setParsed([])
      setUnrecognized(false)
      setBrokerHint(null)
      setDiagnostics(null)
      setCsvSupportFile(null)
      lastCsvFileRef.current = null
      resetFileInput()
      notifyGettingStartedChecklistMaybeCompleted()
      onImportSuccess?.({
        count: importedCount,
        skipped,
        errorSummary: errLines || undefined,
      })
    }

    endImport()
  }

  const isTradovateFormat = parsed.length > 0 && isTradovateCsvRow(parsed[0])

  return (
    <div className={compact ? "space-y-3" : "space-y-4"}>
      <FeedbackModal {...feedbackModalProps} />
      <CsvImportFailureModal
        open={failureModalOpen}
        submitting={submittingSupport}
        onSubmit={() => void handleSubmitCsvSupport()}
        onTryAnother={handleTryAnotherFile}
        onCancel={handleFailureCancel}
      />
      {unrecognized ? (
        <CsvImportUnsupportedBanner brokerHint={brokerHint} />
      ) : null}

      {diagnostics ? (
        <CsvImportDiagnosticsPanel
          diagnostics={diagnostics}
          compact={compact}
          csvFile={csvSupportFile}
          brokerName={brokerHint ?? diagnostics.formatLabel}
          importedRowCount={parsed.length}
          importableRowCount={parsed.length}
          canImport={!requireSelectedAccount || Boolean(selectedAccount)}
          importDisabledHint="Select an account before importing."
          importing={loading}
          onImportRows={() => void handleImport()}
        />
      ) : null}

      <input
        ref={fileInputRef}
        id={fileInputId}
        type="file"
        accept=".csv"
        onChange={(e) => {
          const file = e.target.files?.[0]
          if (file) void handleFile(file)
        }}
        className="block w-full text-sm text-gray-300 file:mr-3 file:min-h-[44px] file:rounded-lg file:border-0 file:bg-emerald-500/20 file:px-3 file:py-2.5 file:text-sm file:text-emerald-200"
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

      {parsed.length > 0 && !diagnostics ? (
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
      ) : null}
    </div>
  )
}
