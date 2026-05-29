"use client"

import type { CsvImportDiagnostics } from "@/lib/csvImportDiagnostics"

type Props = {
  diagnostics: CsvImportDiagnostics
  compact?: boolean
  className?: string
}

export default function CsvImportDiagnosticsPanel({
  diagnostics,
  compact = false,
  className = "",
}: Props) {
  const {
    formatLabel,
    detectedColumns,
    missingRequired,
    unknownColumns,
    rowFailureSamples,
    explanation,
  } = diagnostics

  return (
    <div
      className={`rounded-xl border border-red-500/25 bg-red-950/30 p-4 text-sm text-red-50/95 ${className}`}
      role="alert"
    >
      <p className="font-semibold text-red-100">CSV import diagnostics</p>
      {explanation ? (
        <p className={`mt-2 leading-relaxed text-red-100/85 ${compact ? "text-xs" : "text-sm"}`}>
          {explanation}
        </p>
      ) : null}
      <p className="mt-2 text-xs text-red-200/70">Detected format: {formatLabel}</p>

      {detectedColumns.length > 0 ? (
        <div className="mt-3">
          <p className="text-xs font-medium uppercase tracking-wide text-red-200/80">
            Supported columns detected
          </p>
          <ul className="mt-1 space-y-0.5">
            {detectedColumns.map((col) => (
              <li key={col} className="text-xs text-emerald-200/90">
                ✓ {col}
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

      {unknownColumns.length > 0 ? (
        <div className="mt-3">
          <p className="text-xs font-medium uppercase tracking-wide text-red-200/80">
            Unknown columns
          </p>
          <ul className="mt-1 space-y-0.5">
            {unknownColumns.map((col) => (
              <li key={col} className="text-xs text-amber-100/90">
                {col}
              </li>
            ))}
          </ul>
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
                <span className="font-medium text-red-100">Row {sample.rowNumber}:</span>{" "}
                {sample.reason}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  )
}
