"use client"

import { useEffect, useState } from "react"
import type { CsvImportDiagnostics } from "@/lib/csvImportDiagnostics"
import { submitCsvDiagnosticsFormat } from "@/lib/submitCsvDiagnosticsFormat"
import { supabase } from "@/lib/supabaseClient"

type Props = {
  diagnostics: CsvImportDiagnostics
  compact?: boolean
  className?: string
  /** Original CSV file for csv-support upload (required for submit CTA). */
  csvFile?: File | null
  /** Broker label for support request; falls back to detected format label. */
  brokerName?: string | null
  /** Data row count shown in auto-generated notes. */
  importedRowCount?: number
  /** Parsed trades ready to import (shows footer import actions when > 0). */
  importableRowCount?: number
  /** When false, import buttons are disabled (e.g. no account selected). */
  canImport?: boolean
  importDisabledHint?: string
  importing?: boolean
  /** Import parsed rows — same handler as the normal Import button. */
  onImportRows?: () => void | Promise<void>
}

export default function CsvImportDiagnosticsPanel({
  diagnostics,
  compact = false,
  className = "",
  csvFile = null,
  brokerName = null,
  importedRowCount = 0,
  importableRowCount = 0,
  canImport = true,
  importDisabledHint = "Select an account above before importing.",
  importing = false,
  onImportRows,
}: Props) {
  const [submittingFormat, setSubmittingFormat] = useState(false)
  const [formatSubmitted, setFormatSubmitted] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)

  const {
    formatLabel,
    detectedColumns,
    supportedColumnCount,
    calculatedFields,
    missingRequired,
    unknownColumns,
    unknownColumnCount,
    rowFailureSamples,
    explanation,
    successPreview,
    rrImportNote,
  } = diagnostics

  const heavyUnknownFields = unknownColumnCount >= 3
  const resolvedBroker =
    brokerName?.trim() || formatLabel?.trim() || "Unknown Broker"
  const showImportFooter = importableRowCount > 0 && Boolean(onImportRows)
  const showStandaloneFormatSubmit =
    unknownColumnCount > 0 && !showImportFooter
  const showCombinedPrimary =
    showImportFooter && unknownColumnCount > 0 && Boolean(csvFile)

  useEffect(() => {
    setFormatSubmitted(false)
    setSubmitError(null)
  }, [unknownColumns.join("\0"), formatLabel, importableRowCount])

  async function trySubmitFormatSilently(): Promise<boolean> {
    if (formatSubmitted) return true
    if (!csvFile) return false

    setSubmittingFormat(true)
    setSubmitError(null)

    const result = await submitCsvDiagnosticsFormat(supabase, {
      csvFile,
      diagnostics,
      brokerName: resolvedBroker,
      importedRowCount,
    })

    setSubmittingFormat(false)

    if (!result.ok) {
      console.error("[csv-diagnostics] format submit failed (import continues)", {
        message: result.message,
      })
      setSubmitError(result.message)
      return false
    }

    setFormatSubmitted(true)
    return true
  }

  async function handleSubmitFormatOnly() {
    if (submittingFormat || importing || formatSubmitted) return
    await trySubmitFormatSilently()
  }

  async function handleSubmitFormatAndImport() {
    if (importing || submittingFormat || !onImportRows) return
    if (!canImport) return

    await trySubmitFormatSilently()
    await onImportRows()
  }

  async function handleImportOnly() {
    if (importing || submittingFormat || !onImportRows || !canImport) return
    await onImportRows()
  }

  const importBusy = importing || submittingFormat
  const importLabel = importing
    ? "Importing…"
    : submittingFormat
      ? "Submitting format…"
      : `Import ${importableRowCount} Row${importableRowCount === 1 ? "" : "s"}`

  return (
    <div className={className}>
      <div
        className={`rounded-xl border p-4 text-sm ${
          successPreview
            ? "border-emerald-500/30 bg-emerald-950/25 text-emerald-50/95"
            : "border-red-500/25 bg-red-950/30 text-red-50/95"
        }`}
        role={successPreview ? "status" : "alert"}
      >
        <p
          className={`font-semibold ${
            successPreview ? "text-emerald-100" : "text-red-100"
          }`}
        >
          {successPreview
            ? `✓ ${formatLabel} format detected`
            : "CSV import diagnostics"}
        </p>
        {explanation ? (
          <p
            className={`mt-2 leading-relaxed ${
              successPreview ? "text-emerald-100/85" : "text-red-100/85"
            } ${compact ? "text-xs" : "text-sm"}`}
          >
            {explanation}
          </p>
        ) : null}
        {!successPreview ? (
          <p className="mt-2 text-xs text-red-200/70">
            Detected format: {formatLabel}
          </p>
        ) : null}

        {detectedColumns.length > 0 ? (
          <div className="mt-3">
            <p
              className={`text-xs font-medium uppercase tracking-wide ${
                successPreview ? "text-emerald-200/80" : "text-red-200/80"
              }`}
            >
              {successPreview
                ? "Supported fields detected"
                : `Supported fields detected (${supportedColumnCount})`}
            </p>
            <ul className="mt-1 space-y-0.5">
              {detectedColumns.map((col) => (
                <li
                  key={col}
                  className={`text-xs ${
                    successPreview ? "text-emerald-200/90" : "text-emerald-200/90"
                  }`}
                >
                  ✓ {col}
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {rrImportNote ? (
          <p
            className={`mt-3 text-xs ${
              rrImportNote.startsWith("✓")
                ? successPreview
                  ? "text-emerald-200/90"
                  : "text-emerald-200/90"
                : successPreview
                  ? "text-emerald-100/70"
                  : "text-red-100/70"
            }`}
          >
            {rrImportNote}
          </p>
        ) : null}

        {calculatedFields.length > 0 ? (
          <div className="mt-3">
            <p className="text-xs font-medium uppercase tracking-wide text-emerald-200/80">
              Calculated
            </p>
            <ul className="mt-1 space-y-0.5">
              {calculatedFields.map((field) => (
                <li key={field} className="text-xs text-emerald-200/90">
                  ✓ {field}
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {missingRequired.length > 0 ? (
          <div className="mt-3">
            <p className="text-xs font-medium uppercase tracking-wide text-red-200/80">
              Missing required fields
            </p>
            <ul className="mt-1 space-y-0.5">
              {missingRequired.map((col) => (
                <li key={col} className="text-xs text-red-200/95">
                  ✗ {col}
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {unknownColumnCount > 0 ? (
          <div
            className={`mt-3 rounded-lg border p-3 ${
              heavyUnknownFields
                ? "border-amber-500/40 bg-amber-950/25"
                : "border-white/10 bg-black/20"
            }`}
          >
            <p
              className={`text-xs font-medium uppercase tracking-wide ${
                heavyUnknownFields ? "text-amber-200" : "text-red-200/80"
              }`}
            >
              {heavyUnknownFields
                ? "⚠ Additional broker-specific fields detected"
                : `Unknown columns (${unknownColumnCount})`}
            </p>
            <ul className="mt-1 space-y-0.5">
              {unknownColumns.map((col) => (
                <li key={col} className="text-xs text-amber-100/90">
                  {col}
                </li>
              ))}
            </ul>

            {showImportFooter ? (
              <p className="mt-3 text-xs leading-relaxed text-gray-200/90">
                We detected columns TradeTraxs doesn&apos;t recognize yet. Use
                the button below to send this format for review{" "}
                <span className="text-white/90">and import your parsed rows</span>
                .
              </p>
            ) : showStandaloneFormatSubmit ? (
              <div className="mt-3 space-y-2 border-t border-white/10 pt-3">
                {formatSubmitted ? (
                  <div className="rounded-lg border border-emerald-500/30 bg-emerald-950/30 p-3 text-xs text-emerald-100/95">
                    <p className="font-semibold text-emerald-100">
                      Thanks! This CSV format has been submitted to TradeTraxs.
                    </p>
                    <p className="mt-1 leading-relaxed text-emerald-100/85">
                      We&apos;ll review unsupported fields and improve
                      compatibility.
                    </p>
                  </div>
                ) : (
                  <>
                    <p className="text-xs leading-relaxed text-gray-200/90">
                      We detected columns that TradeTraxs doesn&apos;t currently
                      recognize.
                    </p>
                    <p className="text-xs leading-relaxed text-gray-300/80">
                      This CSV can help us improve broker support.
                    </p>
                    {submitError ? (
                      <p className="text-xs text-red-300">{submitError}</p>
                    ) : null}
                    <button
                      type="button"
                      onClick={() => void handleSubmitFormatOnly()}
                      disabled={submittingFormat || !csvFile}
                      className="w-full rounded-lg border border-blue-400/30 bg-blue-500/15 px-3 py-2 text-xs font-semibold text-blue-100 transition hover:bg-blue-500/25 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto sm:px-4 sm:text-sm"
                    >
                      {submittingFormat
                        ? "Submitting…"
                        : "Submit CSV Format to TradeTraxs"}
                    </button>
                  </>
                )}
              </div>
            ) : null}
          </div>
        ) : null}

        {rowFailureSamples.length > 0 ? (
          <div className="mt-3">
            <p className="text-xs font-medium uppercase tracking-wide text-red-200/80">
              Row errors (first {rowFailureSamples.length})
            </p>
            <ul className="mt-1 space-y-1">
              {rowFailureSamples.map((sample) => (
                <li key={sample.rowNumber} className="text-xs text-red-100/80">
                  <span className="font-medium text-red-100">
                    Row {sample.rowNumber}:
                  </span>{" "}
                  {sample.reason}
                </li>
              ))}
            </ul>
          </div>
        ) : null}
      </div>

      {showImportFooter ? (
        <div className="mt-3 rounded-xl border border-emerald-500/30 bg-emerald-950/20 p-4">
          <p className="text-sm font-semibold text-emerald-100">
            {importableRowCount} row{importableRowCount === 1 ? "" : "s"} ready
            to import
          </p>
          <p className="mt-1 text-xs leading-relaxed text-emerald-100/75">
            {showCombinedPrimary
              ? "Submit this CSV format to TradeTraxs and import your parsed rows in one step."
              : "Import parsed rows into your selected account."}
          </p>

          {formatSubmitted ? (
            <p className="mt-2 text-xs text-emerald-200/90">
              CSV format submitted. Thank you.
            </p>
          ) : submitError && showCombinedPrimary ? (
            <p className="mt-2 text-xs text-amber-200/90">
              Format submit failed ({submitError}). Import will still run.
            </p>
          ) : null}

          {!canImport ? (
            <p className="mt-2 text-xs text-amber-200/90">{importDisabledHint}</p>
          ) : null}

          <div className="mt-3">
            <button
              type="button"
              onClick={() =>
                void (showCombinedPrimary
                  ? handleSubmitFormatAndImport()
                  : handleImportOnly())
              }
              disabled={importBusy || !canImport}
              className="w-full rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto disabled:hover:bg-blue-500"
            >
              {showCombinedPrimary
                ? importBusy
                  ? submittingFormat && !importing
                    ? "Submitting format…"
                    : "Working…"
                  : `Submit Format & Import ${importableRowCount} Row${importableRowCount === 1 ? "" : "s"}`
                : importLabel}
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
