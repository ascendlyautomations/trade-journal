"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import { submitFeatureRequest } from "@/lib/featureRequests"
import {
  submissionFormCard,
  submissionHistoryCard,
  submissionHistoryItem,
  submissionHistoryList,
  submissionInput,
  submissionLabel,
  submissionPageContainer,
  submissionPageShell,
  submissionStatusPill,
  submissionSubmitButton,
  submissionSubtitle,
  submissionTextarea,
  submissionTitle,
} from "@/lib/submissionFormStyles"
import { useUserProfile } from "@/lib/useUserProfile"

type FeatureRequestRow = {
  id: string
  title: string
  status: string | null
  created_at: string | null
}

export default function FeatureRequestsPage() {
  const router = useRouter()
  const { user, loading: profileLoading } = useUserProfile()
  const [title, setTitle] = useState("")
  const [description, setDescription] = useState("")
  const [loading, setLoading] = useState(false)
  const submittingRef = useRef(false)
  const [success, setSuccess] = useState("")
  const [error, setError] = useState("")
  const [history, setHistory] = useState<FeatureRequestRow[]>([])
  const [historyLoading, setHistoryLoading] = useState(true)

  const loadHistory = useCallback(async (userId: string) => {
    setHistoryLoading(true)
    const { data, error: qErr } = await supabase
      .from("feature_requests")
      .select("id, title, status, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(25)

    if (qErr) {
      console.error("[feature-requests] history fetch failed", qErr)
      setHistory([])
    } else {
      setHistory((data as FeatureRequestRow[]) || [])
    }
    setHistoryLoading(false)
  }, [])

  useEffect(() => {
    if (profileLoading) return
    if (!user?.id) {
      setHistory([])
      setHistoryLoading(false)
      return
    }
    void loadHistory(user.id)
  }, [loadHistory, profileLoading, user?.id])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim() || !description.trim() || submittingRef.current || loading) return

    submittingRef.current = true
    setLoading(true)
    setSuccess("")
    setError("")

    try {
      if (!user?.id) {
        router.push("/login")
        return
      }

      const result = await submitFeatureRequest(user.id, {
        title,
        description,
      })

      if (!result.ok) {
        setError(result.message)
        return
      }

      setTitle("")
      setDescription("")
      setSuccess("Feature request submitted. Thank you!")
      await loadHistory(user.id)
    } finally {
      submittingRef.current = false
      setLoading(false)
    }
  }

  return (
    <>
      <div className={submissionPageShell}>
        <div className={submissionPageContainer}>
          <form onSubmit={handleSubmit} className={submissionFormCard}>
            <h1 className={submissionTitle}>Submit Feature Request</h1>
            <p className={submissionSubtitle}>
              Have an idea that would make TradeTraxs even better?
              <br />
              We&apos;d love to hear it.
            </p>

            <label className={submissionLabel}>Title</label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Short summary"
              className={submissionInput}
              maxLength={200}
            />

            <label className={submissionLabel}>Description</label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What problem does this solve? How would it work?"
              rows={6}
              className={submissionTextarea}
            />

            {error ? <p className="mb-3 text-sm text-red-300">{error}</p> : null}
            {success ? <p className="mb-3 text-sm text-emerald-300">{success}</p> : null}

            <button
              type="submit"
              disabled={loading || !title.trim() || !description.trim()}
              className={submissionSubmitButton}
            >
              {loading ? "Submitting..." : "Submit Feature Request"}
            </button>
          </form>

          <section className={submissionHistoryCard}>
            <h2 className="text-lg font-semibold text-white">Your recent feature requests</h2>
            <p className="mt-1 text-sm text-gray-400">
              Title, status, and date for requests you submitted.
            </p>
            {historyLoading ? (
              <p className="mt-4 text-sm text-gray-400">Loading...</p>
            ) : !history.length ? (
              <p className="mt-4 text-sm text-gray-400">No feature requests yet.</p>
            ) : (
              <ul className={submissionHistoryList}>
                {history.map((row) => (
                  <li key={row.id} className={submissionHistoryItem}>
                    <span className="font-medium text-gray-100">{row.title}</span>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-gray-400">
                      <span className={submissionStatusPill}>
                        {row.status || "open"}
                      </span>
                      <span className="tabular-nums">
                        {row.created_at
                          ? new Date(row.created_at).toLocaleString()
                          : "—"}
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
