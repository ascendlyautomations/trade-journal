"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"

type SupportListTab = "unviewed" | "viewed" | "open" | "in_progress" | "resolved"

const CATEGORY_LABELS: Record<string, string> = {
  bug: "Bug",
  account: "Account",
  billing: "Billing",
  csv_import: "CSV Import",
  feature_request: "Feature Request",
  general: "General",
}

function categoryLabel(value: string | null | undefined) {
  if (!value) return "—"
  return CATEGORY_LABELS[value] || value
}

function previewMessage(text: string | null | undefined, max = 120) {
  const t = (text || "").replace(/\s+/g, " ").trim()
  if (!t) return "—"
  return t.length > max ? `${t.slice(0, max)}…` : t
}

export default function AdminSupportPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [adminUserId, setAdminUserId] = useState<string | null>(null)
  const [rows, setRows] = useState<any[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<SupportListTab>("unviewed")
  const [selected, setSelected] = useState<any | null>(null)
  const [detailViewed, setDetailViewed] = useState(false)
  const [detailStatus, setDetailStatus] = useState("open")
  const [detailAdminNotes, setDetailAdminNotes] = useState("")
  const [savingDetail, setSavingDetail] = useState(false)
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)

  async function fetchRows(tab: SupportListTab) {
    if (!allowed) return
    setListLoading(true)
    let query = supabase
      .from("support_tickets")
      .select(
        "id, user_id, email, category, subject, message, screenshot_url, status, priority, admin_notes, created_at, updated_at, viewed, viewed_at, viewed_by"
      )
      .order("created_at", { ascending: false })

    if (tab === "unviewed") query = query.eq("viewed", false)
    if (tab === "viewed") query = query.eq("viewed", true)
    if (tab === "open") query = query.eq("status", "open")
    if (tab === "in_progress") query = query.eq("status", "in_progress")
    if (tab === "resolved") query = query.eq("status", "resolved")

    const { data, error } = await query
    if (error) {
      console.error("[admin-support] fetch failed", error)
      setRows([])
    } else {
      setRows(data || [])
    }
    setListLoading(false)
  }

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()

      if (process.env.NODE_ENV !== "production") {
        console.debug("[admin-check][/admin/support] resolved", {
          userId: check.userId,
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
    void fetchRows(activeTab)
  }, [allowed, activeTab])

  function openDetail(row: any) {
    setSelected(row)
    setDetailViewed(Boolean(row.viewed))
    setDetailStatus(String(row.status || "open"))
    setDetailAdminNotes(String(row.admin_notes || ""))
  }

  async function handleSaveDetail() {
    if (!selected?.id) return
    setSavingDetail(true)

    const updatePayload: Record<string, unknown> = {
      viewed: detailViewed,
      status: detailStatus.trim() || "open",
      admin_notes: detailAdminNotes.trim() || null,
      updated_at: new Date().toISOString(),
      viewed_at: detailViewed ? new Date().toISOString() : null,
      viewed_by: detailViewed ? adminUserId : null,
    }

    const { error } = await supabase.from("support_tickets").update(updatePayload).eq("id", selected.id)

    if (error) {
      console.error("[admin-support] save failed", error)
      alert("Failed to save support ticket.")
      setSavingDetail(false)
      return
    }

    setSelected(null)
    setSavingDetail(false)
    await fetchRows(activeTab)
  }

  if (checking || !allowed) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access...
        </div>
      </>
    )
  }

  const tabBtn = (tab: SupportListTab, label: string) => (
    <button
      type="button"
      onClick={() => setActiveTab(tab)}
      className={`rounded px-3 py-1.5 text-sm ${
        activeTab === tab ? "bg-blue-500 text-white" : "bg-white/10 text-gray-200 hover:bg-white/20"
      }`}
    >
      {label}
    </button>
  )

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-3xl">
              Support tickets
            </h1>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <p className="mb-3 text-sm text-gray-400">
              Queues by triage and status. Saving updates viewed, status, and notes; the ticket moves to the matching
              tab automatically.
            </p>
            <div className="flex flex-wrap gap-2">
              {tabBtn("unviewed", "Unviewed")}
              {tabBtn("viewed", "Viewed")}
              {tabBtn("open", "Open")}
              {tabBtn("in_progress", "In progress")}
              {tabBtn("resolved", "Resolved")}
            </div>

            {listLoading ? (
              <p className="mt-4 text-sm text-gray-300">Loading tickets...</p>
            ) : !rows.length ? (
              <p className="mt-4 text-sm text-gray-300">No tickets in this queue.</p>
            ) : (
              <div className="mt-4 space-y-2">
                {rows.map((row) => (
                  <button
                    key={row.id}
                    type="button"
                    onClick={() => openDetail(row)}
                    className="w-full rounded-lg border border-white/10 bg-black/20 p-3 text-left transition hover:bg-black/30"
                  >
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <p className="min-w-0 flex-1 truncate font-medium text-white">{row.subject || "No subject"}</p>
                      <div className="flex shrink-0 flex-wrap items-center gap-1.5">
                        <span className="rounded bg-white/10 px-2 py-0.5 text-xs text-gray-200">
                          {categoryLabel(row.category)}
                        </span>
                        <span className="rounded bg-emerald-500/20 px-2 py-0.5 text-xs capitalize text-emerald-200">
                          {row.status || "open"}
                        </span>
                        {row.screenshot_url ? (
                          <span className="rounded bg-blue-500/25 px-2 py-0.5 text-xs text-blue-100">Screenshot</span>
                        ) : null}
                      </div>
                    </div>
                    <p className="mt-1 line-clamp-2 text-sm text-gray-300">{previewMessage(row.message)}</p>
                    <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs text-gray-500">
                      <span className="truncate">{row.email || row.user_id || "Unknown user"}</span>
                      <span className="shrink-0 tabular-nums">
                        {row.created_at ? new Date(row.created_at).toLocaleString() : "—"}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>

      {selected ? (
        <div
          className="fixed inset-0 z-[130] flex items-center justify-center bg-black/70 p-3 backdrop-blur-sm md:p-6"
          onClick={() => setSelected(null)}
        >
          <div
            className="max-h-[90vh] w-full max-w-3xl overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-4 text-white md:p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0 flex-1">
                <p className="text-xs text-gray-400">
                  {categoryLabel(selected.category)} ·{" "}
                  {selected.created_at ? new Date(selected.created_at).toLocaleString() : "—"}
                </p>
                <h3 className="mt-1 text-xl font-semibold">{selected.subject || "No subject"}</h3>
                <p className="mt-1 text-xs text-gray-400">
                  {selected.email || selected.user_id || "Unknown user"}
                </p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
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
                  onClick={() => setSelected(null)}
                  className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20"
                >
                  Close
                </button>
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded border border-white/10 bg-black/20 p-3">
                <p className="text-xs text-gray-400">Message</p>
                <p className="mt-1 whitespace-pre-wrap text-sm text-gray-200">{selected.message || "—"}</p>
              </div>

              {selected.screenshot_url ? (
                <div className="rounded border border-white/10 bg-black/20 p-3">
                  <p className="mb-2 text-xs text-gray-400">Screenshot</p>
                  <img
                    src={selected.screenshot_url}
                    alt=""
                    className="max-h-[320px] w-full cursor-zoom-in rounded border border-white/10 bg-black/40 object-contain"
                    onClick={() => setLightboxUrl(selected.screenshot_url)}
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
                <div className="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2">
                  <div>
                    <label className="text-xs text-gray-400">Status</label>
                    <select
                      value={detailStatus}
                      onChange={(e) => setDetailStatus(e.target.value)}
                      className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm"
                    >
                      <option value="open">open</option>
                      <option value="in_progress">in_progress</option>
                      <option value="resolved">resolved</option>
                    </select>
                  </div>
                  <div>
                    <label className="text-xs text-gray-400">Admin notes</label>
                    <textarea
                      value={detailAdminNotes}
                      onChange={(e) => setDetailAdminNotes(e.target.value)}
                      rows={4}
                      className="mt-1 w-full rounded border border-white/10 bg-[#111827] p-2 text-sm"
                      placeholder="Internal notes..."
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
