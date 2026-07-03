"use client"

import InputTradeForm from "../components/InputTradeForm"
import QuickTradeModal from "../components/QuickTradeModal"
import CsvImportFailureModal from "../components/CsvImportFailureModal"
import { useState, useRef, useEffect } from "react"
import Papa from "papaparse"
import { supabase } from "../../lib/supabaseClient"
import { buildTradesFromParsedCsv, stripBom, type CsvRow } from "@/lib/csvTradeParsers"
import {
  detectCsvBrokerHint,
  isCsvFormatUnrecognized,
} from "@/lib/csvBrokerHint"
import {
  buildCsvImportDiagnostics,
  type CsvImportDiagnostics,
} from "@/lib/csvImportDiagnostics"
import { buildCsvSupportNotes } from "@/lib/csvImportSupportNotes"
import { submitCsvSupportRequest } from "@/lib/submitCsvSupportRequest"
import {
  INPUT_TRADE_PAGE_TITLE_CLASSNAME,
  INPUT_TRADE_PAGE_TITLE_ROW_CLASSNAME,
} from "@/lib/inputTradePageTitle"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { feedbackPresets, persistentSuccess } from "@/lib/feedbackPresets"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { useUserProfile } from "@/lib/useUserProfile"

const INPUT_TRADE_CSV_INPUT_ID = "input-trade-csv-upload"

export default function Home() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user } = useUserProfile()
  const userId = user?.id ?? null
  const [loading, setLoading] = useState(false)
  const [reviewCount, setReviewCount] = useState(0)
  const [parsedTrades, setParsedTrades] = useState<any[]>([])
  const [csvUnrecognized, setCsvUnrecognized] = useState(false)
  const [csvBrokerHint, setCsvBrokerHint] = useState<string | null>(null)
  const [csvDiagnostics, setCsvDiagnostics] = useState<CsvImportDiagnostics | null>(null)
  const [csvSupportFile, setCsvSupportFile] = useState<File | null>(null)
  const [csvDataRowCount, setCsvDataRowCount] = useState(0)
  const [failureModalOpen, setFailureModalOpen] = useState(false)
  const [failureReason, setFailureReason] = useState("")
  const [submittingSupport, setSubmittingSupport] = useState(false)
  const [showQuickTrade, setShowQuickTrade] = useState(false)

  const csvInputRef = useRef<HTMLInputElement>(null)
  const lastCsvFileRef = useRef<File | null>(null)

  useEffect(() => {
    void fetchReviewCount()
  }, [userId])

  function resetCsvInput() {
    if (csvInputRef.current) csvInputRef.current.value = ""
  }

  function clearCsvUploadState() {
    setParsedTrades([])
    setCsvUnrecognized(false)
    setCsvBrokerHint(null)
    setCsvDiagnostics(null)
    setCsvSupportFile(null)
    setCsvDataRowCount(0)
    lastCsvFileRef.current = null
    resetCsvInput()
  }

  function openFailureModal(reason: string) {
    setFailureReason(reason)
    setFailureModalOpen(true)
  }

  async function handleCSVUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return

    lastCsvFileRef.current = file
    setCsvSupportFile(file)
    setFailureModalOpen(false)
    setLoading(true)

    if (!userId) {
      showPopup({ type: "info", message: "Please log in first" })
      setLoading(false)
      return
    }

    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("is_pro, has_used_csv_import")
      .eq("id", userId)
      .single()

    if (profileErr || !profile) {
      console.error("Profile fetch failed:", profileErr)
      showPopup({ type: "error", message: "Could not verify account. Try again." })
      setLoading(false)
      return
    }

    if (!profile.is_pro && profile.has_used_csv_import) {
      showPopup(feedbackPresets.csvImportUnavailable())
      setLoading(false)
      resetCsvInput()
      return
    }

    if (file.size === 0) {
      clearCsvUploadState()
      lastCsvFileRef.current = file
      openFailureModal("The file is empty.")
      setLoading(false)
      return
    }

    let text: string
    try {
      text = await file.text()
    } catch {
      clearCsvUploadState()
      lastCsvFileRef.current = file
      openFailureModal("Could not read the file.")
      setLoading(false)
      return
    }

    if (text.trim() === "undefined") {
      clearCsvUploadState()
      lastCsvFileRef.current = file
      openFailureModal('File content is invalid ("undefined").')
      setLoading(false)
      return
    }

    Papa.parse<CsvRow>(file, {
      header: true,
      skipEmptyLines: true,
      transformHeader: (h: string) => stripBom(String(h).trim()),
      error: (err) => {
        clearCsvUploadState()
        lastCsvFileRef.current = file
        openFailureModal(err.message || "Could not parse CSV file.")
        setLoading(false)
      },
      complete: (results) => {
        const fields = (results.meta.fields ?? []).map((f) => stripBom(String(f).trim()))
        const hasHeaders = fields.some((f) => f.length > 0)
        const rows = (results.data || []).filter(
          (r): r is CsvRow =>
            !!r && typeof r === "object" && Object.keys(r).length > 0
        )

        if (!hasHeaders) {
          setParsedTrades([])
          setCsvUnrecognized(false)
          setCsvBrokerHint(null)
          setCsvDiagnostics(null)
          openFailureModal("No column headers found in CSV.")
          setLoading(false)
          return
        }

        if (rows.length === 0) {
          setParsedTrades([])
          setCsvUnrecognized(false)
          setCsvBrokerHint(null)
          setCsvDiagnostics(null)
          openFailureModal("No data rows found in CSV.")
          setLoading(false)
          return
        }

        const parsed = buildTradesFromParsedCsv(rows, user.id)
        const diag = buildCsvImportDiagnostics(rows, parsed)
        const unrecognized = isCsvFormatUnrecognized(parsed.summary)

        setParsedTrades(parsed.parsedTrades)
        setCsvUnrecognized(unrecognized)
        setCsvBrokerHint(detectCsvBrokerHint(rows))
        setCsvDiagnostics(diag)
        setCsvDataRowCount(rows.length)

        if (unrecognized || parsed.parsedTrades.length === 0) {
          openFailureModal("Unsupported CSV format — no rows could be imported.")
        }

        setLoading(false)
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

    if (!userId) {
      showPopup(feedbackPresets.importFailed("Please log in first."))
      setSubmittingSupport(false)
      return
    }

    const notes = buildCsvSupportNotes({
      failureReason,
      diagnostics: csvDiagnostics,
      source: "input_trade_page",
      originalFilename: file.name,
    })

    const result = await submitCsvSupportRequest(supabase, {
      csvFile: file,
      brokerName: csvBrokerHint ?? "Unknown",
      notes,
      userId,
    })

    setSubmittingSupport(false)

    if (!result.ok) {
      showPopup(feedbackPresets.importFailed(result.message))
      return
    }

    setFailureModalOpen(false)
    clearCsvUploadState()
    showPopup(
      persistentSuccess(
        "CSV submitted",
        "We'll review this format and work on adding support."
      )
    )
  }

  function handleTryAnotherFile() {
    openCsvFilePicker()
    setFailureModalOpen(false)
    lastCsvFileRef.current = null
    setParsedTrades([])
    setCsvUnrecognized(false)
    setCsvBrokerHint(null)
    setCsvDiagnostics(null)
  }

  function handleFailureCancel() {
    setFailureModalOpen(false)
    clearCsvUploadState()
  }

  function openCsvFilePicker() {
    const input = csvInputRef.current
    if (!input) return
    input.value = ""
    input.click()
  }

  async function fetchReviewCount() {
    if (!userId) {
      setReviewCount(0)
      return
    }

    const { count } = await supabase
      .from("trades")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("is_initial_import", true)
      .eq("reviewed", false)

    setReviewCount(count || 0)
  }

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <CsvImportFailureModal
        open={failureModalOpen}
        submitting={submittingSupport}
        onSubmit={() => void handleSubmitCsvSupport()}
        onTryAnother={handleTryAnotherFile}
        onCancel={handleFailureCancel}
      />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="pt-2 px-4 pb-4 md:px-6 md:pb-5 max-w-8xl mx-auto">
          <div className={INPUT_TRADE_PAGE_TITLE_ROW_CLASSNAME}>
            <h1 className={INPUT_TRADE_PAGE_TITLE_CLASSNAME}>Input Trade</h1>
          </div>

          <input
            id={INPUT_TRADE_CSV_INPUT_ID}
            ref={csvInputRef}
            type="file"
            accept=".csv,text/csv"
            tabIndex={-1}
            aria-hidden
            className="fixed left-0 top-0 h-px w-px overflow-hidden opacity-0"
            onChange={(e) => void handleCSVUpload(e)}
          />

          <InputTradeForm
            onQuickInputClick={() => {
              if (isDemoModeActive()) {
                requestDemoSignup("trade")
                return
              }
              setShowQuickTrade(true)
            }}
            onUploadCsvClick={openCsvFilePicker}
            onReviewCsvClick={() => {
              window.location.href = "/review"
            }}
            reviewCount={reviewCount}
            csvLoading={loading}
            parsedTrades={parsedTrades}
            csvUnrecognized={csvUnrecognized}
            csvBrokerHint={csvBrokerHint}
            csvDiagnostics={csvDiagnostics}
            csvSupportFile={csvSupportFile}
            csvDataRowCount={csvDataRowCount}
            onParsedTradesClear={() => {
              clearCsvUploadState()
              fetchReviewCount()
            }}
          />
        </div>
      </div>

      <QuickTradeModal
        open={showQuickTrade}
        userId={userId}
        onClose={() => setShowQuickTrade(false)}
        onSaved={() => {
          void fetchReviewCount()
        }}
      />
    </>
  )
}
