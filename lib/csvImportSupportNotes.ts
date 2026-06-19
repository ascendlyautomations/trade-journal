import type { CsvImportDiagnostics } from "@/lib/csvImportDiagnostics"

export function buildCsvSupportNotes(options: {
  failureReason?: string | null
  diagnostics?: CsvImportDiagnostics | null
  source?: string
  originalFilename?: string | null
}): string {
  const lines: string[] = []

  if (options.source) {
    lines.push(`Source: ${options.source}`)
  }
  if (options.originalFilename) {
    lines.push(`Original filename: ${options.originalFilename}`)
  }
  if (options.failureReason?.trim()) {
    lines.push(`Failure: ${options.failureReason.trim()}`)
  }

  const diag = options.diagnostics
  if (diag) {
    lines.push(`Detected format: ${diag.formatLabel}`)
    if (diag.explanation) lines.push(diag.explanation)
    if (diag.missingRequired.length) {
      lines.push(`Missing required: ${diag.missingRequired.join(", ")}`)
    }
    if (diag.unknownColumns.length) {
      lines.push(`Unknown columns: ${diag.unknownColumns.slice(0, 20).join(", ")}`)
    }
    if (diag.rowFailureSamples.length) {
      const samples = diag.rowFailureSamples
        .map((s) => `Row ${s.rowNumber}: ${s.reason}`)
        .join("; ")
      lines.push(`Row errors: ${samples}`)
    }
  }

  return lines.join("\n")
}
