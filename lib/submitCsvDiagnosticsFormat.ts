import type { SupabaseClient } from "@supabase/supabase-js"
import type { CsvImportDiagnostics } from "@/lib/csvImportDiagnostics"
import { buildCsvDiagnosticsSubmitNotes } from "@/lib/csvImportSupportNotes"
import { submitCsvSupportRequest } from "@/lib/submitCsvSupportRequest"

export async function submitCsvDiagnosticsFormat(
  supabase: SupabaseClient,
  args: {
    csvFile: File
    diagnostics: CsvImportDiagnostics
    brokerName: string
    importedRowCount: number
  }
): Promise<{ ok: true } | { ok: false; message: string }> {
  const broker = args.brokerName.trim() || args.diagnostics.formatLabel.trim() || "Unknown Broker"
  const notes = buildCsvDiagnosticsSubmitNotes({
    diagnostics: args.diagnostics,
    brokerName: broker,
    importedRowCount: args.importedRowCount,
  })

  return submitCsvSupportRequest(supabase, {
    csvFile: args.csvFile,
    brokerName: broker,
    notes,
  })
}
