"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"

type FeedbackTab = "unviewed" | "viewed"

export default function AdminFeedbackPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [adminUserId, setAdminUserId] = useState<string | null>(null)
  const [feedbackRows, setFeedbackRows] = useState<any[]>([])
  const [feedbackLoading, setFeedbackLoading] = useState(false)
  const [activeFeedbackTab, setActiveFeedbackTab] = useState<FeedbackTab>("unviewed")
  const [selectedFeedback, setSelectedFeedback] = useState<any | null>(null)
  const [detailViewed, setDetailViewed] = useState(false)
  const [detailStatus, setDetailStatus] = useState("open")
  const [detailAdminNotes, setDetailAdminNotes] = useState("")
  const [savingDetail, setSavingDetail] = useState(false)
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)

  async function fetchFeedbackRows(tab: FeedbackTab) {
    if (!allowed) return
    setFeedbackLoading(true)
    let query = supabase
      .from("feedback_submissions")
      .select(
        "id, user_id, email, subject, message, screenshot_url, status, admin_notes, created_at, updated_at, viewed, viewed_at, viewed_by"
      )
      .order("created_at", { ascending: false })

    if (tab === "unviewed") query = query.eq("viewed", false)
    if (tab === "viewed") query = query.eq("viewed", true)

    const { data, error } = await query
    if (error) {
      console.error("[admin-feedback] failed to fetch feedback", error)
      setFeedbackRows([])
    } else {
      setFeedbackRows(data || [])
    }
    setFeedbackLoading(false)
  }

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()

      if (process.env.NODE_ENV !== "production") {
        console.debug("[admin-check][/admin/feedback] resolved", {
          userId: check.userId,
          email: check.email,
          adminRow: check.row,
          error: check.error,
          isAdmin: check.isAdmin,
        })
      }

      if (!check.userId) {
        router.replace("/login")
        return
      }

      if (!check.isAdmin) {
        router.replace("/dashboard")
        return
      }

      if (!cancelled) {
        setAdminUserId(check.userId)
        setAllowed(true)
        setChecking(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [router])

  useEffect(() => {
    if (!allowed) return
    void fetchFeedbackRows(activeFeedbackTab)
  }, [allowed, activeFeedbackTab])

  function openFeedbackDetail(row: any) {
    setSelectedFeedback(row)
    setDetailViewed(Boolean(row.viewed))
    setDetailStatus(String(row.status || "open"))
    setDetailAdminNotes(String(row.admin_notes || ""))
  }

  async function handleSaveDetail() {
    if (!selectedFeedback?.id) return
    setSavingDetail(true)

    const updatePayload: Record<string, unknown> = {
      viewed: detailViewed,
      status: detailStatus.trim() || "open",
      admin_notes: detailAdminNotes.trim() || null,
      updated_at: new Date().toISOString(),
      viewed_at: detailViewed ? new Date().toISOString() : null,
      viewed_by: detailViewed ? adminUserId : null,
    }

    const { error } = await supabase
      .from("feedback_submissions")
      .update(updatePayload)
      .eq("id", selectedFeedback.id)

    if (error) {
      console.error("[admin-feedback] save failed", error)
      alert("Failed to save feedback review state.")
      setSavingDetail(false)
      return
    }

    setSelectedFeedback(null)
    setSavingDetail(false)
    await fetchFeedbackRows(activeFeedbackTab)
  }

  if (checking || !allowed) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-8">
          Checking admin access...
        </div>
      </>
    )
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-4 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex items-center justify-between gap-3">
            <h1 className="text-2xl md:text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Feedback Submissions
            </h1>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setActiveFeedbackTab("unviewed")}
                className={`rounded px-3 py-1.5 text-sm ${
                  activeFeedbackTab === "unviewed"
                    ? "bg-emerald-500 text-white"
                    : "bg-white/10 text-gray-200 hover:bg-white/20"
                }`}
              >
                Unviewed
              </button>
              <button
                type="button"
                onClick={() => setActiveFeedbackTab("viewed")}
                className={`rounded px-3 py-1.5 text-sm ${
                  activeFeedbackTab === "viewed"
                    ? "bg-emerald-500 text-white"
                    : "bg-white/10 text-gray-200 hover:bg-white/20"
                }`}
              >
                Viewed
              </button>
            </div>

            {feedbackLoading ? (
              <p className="mt-4 text-sm text-gray-300">Loading feedback...</p>
            ) : !feedbackRows.length ? (
              <p className="mt-4 text-sm text-gray-300">
                No {activeFeedbackTab} feedback submissions.
              </p>
            ) : (
              <div className="mt-4 space-y-3">
                {feedbackRows.map((row) => (
                  <button
                    key={row.id}
                    type="button"
                    onClick={() => openFeedbackDetail(row)}
                    className="w-full rounded border border-white/10 bg-black/20 p-3 text-left transition hover:bg-black/30"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <p className="font-medium truncate">{row.subject || "No subject"}</p>
                      <span className="text-xs rounded bg-white/10 px-2 py-0.5 shrink-0">
                        {row.status || "open"}
                      </span>
                    </div>
                    <p className="mt-1 text-sm text-gray-300 line-clamp-2">
                      {row.message || "—"}
                    </p>
                    <div className="mt-2 flex items-center justify-between text-xs text-gray-400">
                      <span>{row.email || row.user_id || "Unknown user"}</span>
                      <span>{row.screenshot_url ? "Has screenshot" : "No screenshot"}</span>
                    </div>
                    <p className="mt-1 text-xs text-gray-500">
                      {row.created_at ? new Date(row.created_at).toLocaleString() : "—"}
                    </p>
                  </button>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>

      {selectedFeedback ? (
        <div
          className="fixed inset-0 z-[130] flex items-center justify-center bg-black/70 backdrop-blur-sm p-3 md:p-6"
          onClick={() => setSelectedFeedback(null)}
        >
          <div
            className="w-full max-w-3xl max-h-[90vh] overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-4 md:p-6 text-white"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex items-start justify-between gap-3">
              <div>
                <h3 className="text-xl font-semibold">{selectedFeedback.subject || "No subject"}</h3>
                <p className="mt-1 text-xs text-gray-400">
                  {selectedFeedback.created_at
                    ? new Date(selectedFeedback.created_at).toLocaleString()
                    : "—"}{" "}
                  • {selectedFeedback.email || selectedFeedback.user_id || "Unknown user"}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void handleSaveDetail()}
                  disabled={savingDetail}
                  className="rounded bg-emerald-500 px-3 py-2 text-sm font-semibold hover:bg-emerald-600 disabled:opacity-60"
                >
                  {savingDetail ? "Saving..." : "Save"}
                </button>
                <button
                  type="button"
                  onClick={() => setSelectedFeedback(null)}
                  className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20"
                >
                  Close
                </button>
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded border border-white/10 bg-black/20 p-3">
                <p className="text-xs text-gray-400">Message</p>
                <p className="mt-1 whitespace-pre-wrap text-sm text-gray-200">
                  {selectedFeedback.message || "—"}
                </p>
              </div>

              {selectedFeedback.screenshot_url ? (
                <div className="rounded border border-white/10 bg-black/20 p-3">
                  <p className="text-xs text-gray-400 mb-2">Screenshot</p>
                  <img
                    src={selectedFeedback.screenshot_url}
                    alt=""
                    className="max-h-[320px] w-full cursor-zoom-in rounded border border-white/10 object-contain bg-black/40"
                    onClick={() => setLightboxUrl(selectedFeedback.screenshot_url)}
                  />
                </div>
              ) : null}

              <div className="rounded border border-white/10 bg-black/20 p-3">
                <label className="inline-flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={detailViewed}
                    onChange={(e) => setDetailViewed(e.target.checked)}
                  />
                  Mark as viewed
                </label>
                <div className="mt-3 grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div>
                    <label className="text-xs text-gray-400">Status</label>
                    <select
                      value={detailStatus}
                      onChange={(e) => setDetailStatus(e.target.value)}
                      className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm"
                    >
                      <option value="open">open</option>
                      <option value="planned">planned</option>
                      <option value="in_progress">in_progress</option>
                      <option value="resolved">resolved</option>
                    </select>
                  </div>
                  <div>
                    <label className="text-xs text-gray-400">Admin Notes</label>
                    <textarea
                      value={detailAdminNotes}
                      onChange={(e) => setDetailAdminNotes(e.target.value)}
                      rows={4}
                      className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm"
                      placeholder="Internal admin notes..."
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {lightboxUrl ? (
        <div
          className="fixed inset-0 z-[140] flex items-center justify-center bg-black/85 p-3"
          onClick={() => setLightboxUrl(null)}
        >
          <div className="relative w-full max-w-5xl" onClick={(e) => e.stopPropagation()}>
            <button
              type="button"
              onClick={() => setLightboxUrl(null)}
              className="absolute right-0 top-0 z-10 rounded bg-black/60 px-3 py-1 text-sm text-white hover:bg-black/80"
            >
              Close
            </button>
            <img src={lightboxUrl} alt="" className="max-h-[85vh] w-full rounded object-contain" />
          </div>
        </div>
      ) : null}
    </>
  )
}
