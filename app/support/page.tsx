"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "../components/Navbar"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { notifyAdminSubmission } from "@/lib/notifyAdminSubmission"
import {
  submissionFileBrowse,
  submissionFilePicker,
  submissionFormCard,
  submissionHistoryCard,
  submissionHistoryItem,
  submissionHistoryList,
  submissionInput,
  submissionLabel,
  submissionPageContainer,
  submissionPageShell,
  submissionSelect,
  submissionStatusPill,
  submissionSubmitButton,
  submissionSubtitle,
  submissionTextarea,
  submissionTitle,
} from "@/lib/submissionFormStyles"

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
      let uploadFile: File = image
      if (image.type?.startsWith("image/")) {
        uploadFile = await compressImage(image)
      }
      const filePath = `support/${user.id}/${Date.now()}-${uploadFile.name}`
      const { error: uploadError } = await supabase.storage
        .from("screenshots")
        .upload(filePath, uploadFile, { upsert: false })

      if (uploadError) {
        setError(uploadError.message)
        setLoading(false)
        return
      }

      const { data: publicData } = supabase.storage.from("screenshots").getPublicUrl(filePath)
      screenshotUrl = publicData.publicUrl
    }

    const { data, error: insertError } = await supabase
      .from("support_tickets")
      .insert({
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
      .select("id")
      .single()

    if (insertError) {
      setError(insertError.message)
      setLoading(false)
      return
    }

    if (data?.id) {
      notifyAdminSubmission("support_ticket", data.id)
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
      <div className={submissionPageShell}>
        <div className={submissionPageContainer}>
          <form onSubmit={handleSubmit} className={submissionFormCard}>
            <h1 className={submissionTitle}>Need Help?</h1>
            <p className={submissionSubtitle}>
              Submit a support request and we&apos;ll review it as soon as possible.
            </p>

            <label className={submissionLabel}>Category</label>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className={submissionSelect}
            >
              {CATEGORIES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
            </select>

            <label className={submissionLabel}>Subject</label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="Short summary of your issue"
              className={submissionInput}
            />

            <label className={submissionLabel}>Message</label>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Describe what happened and what you need."
              rows={6}
              className={submissionTextarea}
            />

            <label className={submissionLabel}>Screenshot (optional)</label>
            <label className={submissionFilePicker}>
              <span className="truncate">{image ? image.name : "Choose an image..."}</span>
              <span className={submissionFileBrowse}>Browse</span>
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
              className={submissionSubmitButton}
            >
              {loading ? "Submitting..." : "Submit request"}
            </button>
          </form>

          <section className={submissionHistoryCard}>
            <h2 className="text-lg font-semibold text-white">Your recent requests</h2>
            <p className="mt-1 text-sm text-gray-400">
              Subject, status, and date for tickets you opened.
            </p>
            {historyLoading ? (
              <p className="mt-4 text-sm text-gray-400">Loading...</p>
            ) : !history.length ? (
              <p className="mt-4 text-sm text-gray-400">No support requests yet.</p>
            ) : (
              <ul className={submissionHistoryList}>
                {history.map((row) => (
                  <li key={row.id} className={submissionHistoryItem}>
                    <span className="font-medium text-gray-100">{row.subject}</span>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-gray-400">
                      <span className={submissionStatusPill}>
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
