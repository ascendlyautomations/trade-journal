"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "../components/Navbar"
import { supabase } from "../../lib/supabaseClient"

const CATEGORIES = [
  { value: "bug", label: "Bug" },
  { value: "account", label: "Account" },
  { value: "billing", label: "Billing" },
  { value: "csv_import", label: "CSV Import" },
  { value: "feature_request", label: "Feature Request" },
  { value: "general", label: "General" },
] as const

type SupportRow = {
  id: string
  subject: string
  status: string | null
  created_at: string | null
}

export default function SupportPage() {
  const router = useRouter()
  const [category, setCategory] = useState<string>("general")
  const [subject, setSubject] = useState("")
  const [message, setMessage] = useState("")
  const [image, setImage] = useState<File | null>(null)
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState("")
  const [error, setError] = useState("")
  const [history, setHistory] = useState<SupportRow[]>([])
  const [historyLoading, setHistoryLoading] = useState(true)

  const loadHistory = useCallback(async (userId: string) => {
    setHistoryLoading(true)
    const { data, error: qErr } = await supabase
      .from("support_tickets")
      .select("id, subject, status, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(25)

    if (qErr) {
      console.error("[support] history fetch failed", qErr)
      setHistory([])
    } else {
      setHistory((data as SupportRow[]) || [])
    }
    setHistoryLoading(false)
  }, [])

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (cancelled) return
      if (!user) {
        setHistory([])
        setHistoryLoading(false)
        return
      }
      await loadHistory(user.id)
    })()
    return () => {
      cancelled = true
    }
  }, [loadHistory])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!subject.trim() || !message.trim()) return

    setLoading(true)
    setSuccess("")
    setError("")

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()

    if (authError || !user) {
      setLoading(false)
      router.push("/login")
      return
    }

    let screenshotUrl: string | null = null
    if (image) {
      const safeName = image.name.replace(/\s+/g, "-")
      const filePath = `support/${user.id}/${Date.now()}-${safeName}`
      const { error: uploadError } = await supabase.storage
        .from("screenshots")
        .upload(filePath, image, { upsert: false })

      if (uploadError) {
        setError(uploadError.message)
        setLoading(false)
        return
      }

      const { data: publicData } = supabase.storage.from("screenshots").getPublicUrl(filePath)
      screenshotUrl = publicData.publicUrl
    }

    const { error: insertError } = await supabase.from("support_tickets").insert({
      user_id: user.id,
      email: user.email ?? null,
      category,
      subject: subject.trim(),
      message: message.trim(),
      screenshot_url: screenshotUrl,
      status: "open",
      priority: "normal",
      viewed: false,
    })

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }

    setSubject("")
    setMessage("")
    setImage(null)
    setSuccess("Your support request was submitted. We will review it as soon as possible.")
    setLoading(false)
    await loadHistory(user.id)
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 md:px-6 text-white">
        <div className="mx-auto w-full max-w-2xl space-y-8">
          <form
            onSubmit={handleSubmit}
            className="rounded-2xl border border-white/10 bg-white/10 p-5 md:p-8 shadow-2xl backdrop-blur-xl"
          >
            <h1 className="text-center text-2xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Need help?
            </h1>
            <p className="mt-2 mb-6 text-center text-sm text-gray-300">
              Submit a support request and we&apos;ll review it as soon as possible.
            </p>

            <label className="mb-2 block text-sm text-gray-300">Category</label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="mb-4 w-full rounded-xl border border-white/10 bg-[#111827] px-4 py-3 text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-400"
            >
              {CATEGORIES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
            </select>

            <label className="mb-2 block text-sm text-gray-300">Subject</label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="Short summary of your issue"
              className="mb-4 w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"
            />

            <label className="mb-2 block text-sm text-gray-300">Message</label>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Describe what happened and what you need."
              rows={6}
              className="mb-4 w-full resize-none rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"
            />

            <label className="mb-2 block text-sm text-gray-300">Screenshot (optional)</label>
            <label className="mb-4 flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-gray-200 hover:bg-white/15">
              <span className="truncate">{image ? image.name : "Choose an image..."}</span>
              <span className="rounded bg-white px-3 py-1 text-xs font-medium text-black">Browse</span>
              <input
                type="file"
                accept="image/*"
                onChange={(e) => setImage(e.target.files?.[0] || null)}
                className="hidden"
              />
            </label>

            {error ? <p className="mb-3 text-sm text-red-300">{error}</p> : null}
            {success ? <p className="mb-3 text-sm text-emerald-300">{success}</p> : null}

            <button
              type="submit"
              disabled={loading || !subject.trim() || !message.trim()}
              className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 py-3 font-semibold transition hover:scale-[1.01] disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:scale-100"
            >
              {loading ? "Submitting..." : "Submit request"}
            </button>
          </form>

          <section className="rounded-2xl border border-white/10 bg-white/5 p-5 md:p-6 backdrop-blur-sm">
            <h2 className="text-lg font-semibold text-white">Your recent requests</h2>
            <p className="mt-1 text-sm text-gray-400">Subject, status, and date for tickets you opened.</p>
            {historyLoading ? (
              <p className="mt-4 text-sm text-gray-400">Loading...</p>
            ) : !history.length ? (
              <p className="mt-4 text-sm text-gray-400">No support requests yet.</p>
            ) : (
              <ul className="mt-4 divide-y divide-white/10 rounded-xl border border-white/10 bg-black/20">
                {history.map((row) => (
                  <li key={row.id} className="flex flex-col gap-1 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between">
                    <span className="font-medium text-gray-100">{row.subject}</span>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-gray-400">
                      <span className="rounded bg-white/10 px-2 py-0.5 capitalize text-gray-200">
                        {row.status || "open"}
                      </span>
                      <span className="tabular-nums">
                        {row.created_at ? new Date(row.created_at).toLocaleString() : "—"}
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </>
  )
}
