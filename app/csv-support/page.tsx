"use client"

import { Suspense, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { CSV_SUPPORT_BROKERS } from "@/lib/csvBrokerHint"
import { submitCsvSupportRequest } from "@/lib/submitCsvSupportRequest"
import { useUserProfile } from "@/lib/useUserProfile"

const SUCCESS_MESSAGE =
  "Thank you for helping improve TradeTraxs. Your CSV sample has been submitted and may be used to support additional brokers/platforms in future updates."

function brokerFromQuery(raw: string | null): string {
  if (!raw?.trim()) return ""
  const match = CSV_SUPPORT_BROKERS.find(
    (b) => b.toLowerCase() === raw.trim().toLowerCase()
  )
  return match ?? raw.trim()
}

function CsvSupportForm() {
  const router = useRouter()
  const { user } = useUserProfile()
  const searchParams = useSearchParams()
  const [brokerName, setBrokerName] = useState("")
  const [notes, setNotes] = useState("")
  const [csvFile, setCsvFile] = useState<File | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState(false)

  useEffect(() => {
    const prefill = brokerFromQuery(searchParams.get("broker"))
    if (prefill) setBrokerName(prefill)
  }, [searchParams])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError("")

    const broker = brokerName.trim()
    if (!broker) {
      setError("Please enter your broker or platform name.")
      return
    }
    if (!csvFile) {
      setError("Please attach a CSV file.")
      return
    }

    setLoading(true)

    if (!user?.id) {
      setLoading(false)
      router.push("/login")
      return
    }

    const result = await submitCsvSupportRequest(supabase, {
      csvFile,
      brokerName: broker,
      notes: notes.trim() || null,
      userId: user.id,
    })

    if (!result.ok) {
      setError(result.message)
      setLoading(false)
      return
    }

    setBrokerName("")
    setNotes("")
    setCsvFile(null)
    setSuccess(true)
    setLoading(false)
  }

  if (success) {
    return (
      <div className="rounded-2xl border border-white/10 bg-white/10 p-6 md:p-8 shadow-2xl backdrop-blur-xl">
        <h1 className="text-center text-2xl font-semibold text-blue-300">
          CSV sample received
        </h1>
        <p className="mt-6 text-center text-sm leading-relaxed text-emerald-100/95">
          {SUCCESS_MESSAGE}
        </p>
        <button
          type="button"
          onClick={() => router.push("/app")}
          className="mt-8 w-full rounded-xl border border-white/15 bg-white/10 py-3 text-sm font-medium text-white transition hover:bg-white/15"
        >
          Back to Add Trade
        </button>
      </div>
    )
  }

  return (
    <form
      onSubmit={(e) => void handleSubmit(e)}
      className="rounded-2xl border border-white/10 bg-white/10 p-5 md:p-8 shadow-2xl backdrop-blur-xl"
    >
      <h1 className="text-center text-2xl font-semibold text-blue-300">
        CSV import support
      </h1>
      <p className="mt-2 mb-6 text-center text-sm text-gray-300">
        Share a sample export so we can add support for your broker or platform.
      </p>

      <label className="mb-2 block text-sm text-gray-300">Broker / platform name</label>
      <input
        type="text"
        list="csv-support-brokers"
        value={brokerName}
        onChange={(e) => setBrokerName(e.target.value)}
        placeholder="e.g. Tradovate, NinjaTrader, TopStep"
        className="mb-4 w-full rounded-xl border border-white/10 bg-[#111827] px-4 py-3 text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-400"
        required
      />
      <datalist id="csv-support-brokers">
        {CSV_SUPPORT_BROKERS.map((b) => (
          <option key={b} value={b} />
        ))}
      </datalist>

      <label className="mb-2 block text-sm text-gray-300">Notes (optional)</label>
      <textarea
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        placeholder="Account type, export steps, or anything that helps."
        rows={4}
        className="mb-4 w-full resize-none rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"
      />

      <label className="mb-2 block text-sm text-gray-300">CSV file</label>
      <label className="mb-4 flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-gray-200 hover:bg-white/15">
        <span className="truncate">{csvFile ? csvFile.name : "Choose a .csv file..."}</span>
        <span className="shrink-0 rounded bg-white px-3 py-1 text-xs font-medium text-black">
          Browse
        </span>
        <input
          type="file"
          accept=".csv,text/csv"
          required
          onChange={(e) => setCsvFile(e.target.files?.[0] ?? null)}
          className="hidden"
        />
      </label>

      {error ? <p className="mb-3 text-sm text-red-300">{error}</p> : null}

      <button
        type="submit"
        disabled={loading || !brokerName.trim() || !csvFile}
        className="w-full rounded-xl bg-blue-500 py-3 font-semibold text-white transition hover:bg-blue-600 hover:scale-[1.01] disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 disabled:hover:scale-100"
      >
        {loading ? "Submitting..." : "Submit CSV sample"}
      </button>
    </form>
  )
}

export default function CsvSupportPage() {
  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 md:px-6 text-white">
        <div className="mx-auto w-full max-w-2xl">
          <Suspense
            fallback={
              <div className="rounded-2xl border border-white/10 bg-white/10 p-8 text-center text-sm text-gray-400">
                Loading…
              </div>
            }
          >
            <CsvSupportForm />
          </Suspense>
        </div>
      </div>
    </>
  )
}
