"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import EmptyState from "@/app/components/ui/EmptyState"
import StarRatingDisplay from "@/app/components/beta/StarRatingDisplay"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import type { BetaTestimonialRow } from "@/lib/betaTestimonials"
import { supabase } from "@/lib/supabaseClient"

type StatusFilter = "all" | "pending" | "approved" | "featured"

type AdminBetaTestimonialRow = BetaTestimonialRow & {
  profiles?: {
    username: string | null
    avatar_url: string | null
  } | null
}

const BETA_TESTIMONIAL_ADMIN_SELECT =
  "id, user_id, rating, title, review, pros, cons, would_recommend, approved, featured, created_at, updated_at, profiles(username, avatar_url)" as const

function previewText(text: string | null | undefined, max = 140) {
  const t = (text || "").replace(/\s+/g, " ").trim()
  if (!t) return "—"
  return t.length > max ? `${t.slice(0, max)}…` : t
}

function statusBadgeClass(row: AdminBetaTestimonialRow) {
  if (row.featured && row.approved) return "bg-amber-500/25 text-amber-100"
  if (row.approved) return "bg-emerald-500/25 text-emerald-100"
  return "bg-white/10 text-gray-300"
}

function statusLabel(row: AdminBetaTestimonialRow) {
  if (row.featured && row.approved) return "Featured"
  if (row.approved) return "Approved"
  return "Pending"
}

export default function AdminBetaTestimonialsPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [rows, setRows] = useState<AdminBetaTestimonialRow[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("pending")
  const [search, setSearch] = useState("")
  const [debouncedSearch, setDebouncedSearch] = useState("")
  const [selected, setSelected] = useState<AdminBetaTestimonialRow | null>(null)
  const [savingDetail, setSavingDetail] = useState(false)

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedSearch(search), 300)
    return () => window.clearTimeout(t)
  }, [search])

  async function fetchRows() {
    if (!allowed) return
    setListLoading(true)

    let query = supabase
      .from("beta_testimonials")
      .select(BETA_TESTIMONIAL_ADMIN_SELECT)
      .order("featured", { ascending: false })
      .order("created_at", { ascending: false })

    if (statusFilter === "pending") {
      query = query.eq("approved", false)
    } else if (statusFilter === "approved") {
      query = query.eq("approved", true).eq("featured", false)
    } else if (statusFilter === "featured") {
      query = query.eq("approved", true).eq("featured", true)
    }

    const q = debouncedSearch.trim()
    if (q) {
      query = query.or(`title.ilike.%${q}%,review.ilike.%${q}%`)
    }

    const { data, error } = await query
    if (error) {
      console.error("[admin-beta-testimonials] fetch failed", error)
      setRows([])
    } else {
      setRows((data as AdminBetaTestimonialRow[]) || [])
    }
    setListLoading(false)
  }

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()

      if (!check.userId) {
        router.replace("/login")
        return
      }

      if (!check.isAdmin) {
        router.replace("/dashboard")
        return
      }

      if (!cancelled) {
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
    void fetchRows()
  }, [allowed, statusFilter, debouncedSearch])

  const filteredCountLabel = useMemo(() => {
    const parts: string[] = []
    if (statusFilter !== "all") parts.push(statusFilter)
    if (debouncedSearch.trim()) parts.push(`search: "${debouncedSearch.trim()}"`)
    return parts.length ? parts.join(" · ") : "all testimonials"
  }, [statusFilter, debouncedSearch])

  async function patchRow(
    id: string,
    patch: Partial<Pick<BetaTestimonialRow, "approved" | "featured">>
  ) {
    setSavingDetail(true)
    const { error } = await supabase
      .from("beta_testimonials")
      .update(patch)
      .eq("id", id)

    if (error) {
      console.error("[admin-beta-testimonials] update failed", error)
      alert("Failed to update testimonial.")
      setSavingDetail(false)
      return false
    }

    setSavingDetail(false)
    await fetchRows()
    return true
  }

  async function handleApprove(row: AdminBetaTestimonialRow) {
    const ok = await patchRow(row.id, { approved: true })
    if (ok) setSelected(null)
  }

  async function handleReject(row: AdminBetaTestimonialRow) {
    const ok = await patchRow(row.id, { approved: false, featured: false })
    if (ok) setSelected(null)
  }

  async function handleToggleFeatured(row: AdminBetaTestimonialRow) {
    if (!row.approved) {
      alert("Approve the testimonial before featuring it.")
      return
    }
    const ok = await patchRow(row.id, { featured: !row.featured })
    if (ok && selected?.id === row.id) {
      setSelected({ ...row, featured: !row.featured })
    }
  }

  async function handleDelete(row: AdminBetaTestimonialRow) {
    if (!window.confirm("Delete this testimonial permanently?")) return
    setSavingDetail(true)
    const { error } = await supabase.from("beta_testimonials").delete().eq("id", row.id)
    if (error) {
      console.error("[admin-beta-testimonials] delete failed", error)
      alert("Failed to delete testimonial.")
      setSavingDetail(false)
      return
    }
    setSavingDetail(false)
    setSelected(null)
    await fetchRows()
  }

  const filterBtn = (
    key: string,
    active: boolean,
    label: string,
    onClick: () => void
  ) => (
    <button
      key={key}
      type="button"
      onClick={onClick}
      className={`rounded-lg px-3 py-1.5 text-sm transition ${
        active
          ? "bg-white/15 text-white"
          : "text-gray-400 hover:bg-white/10 hover:text-gray-200"
      }`}
    >
      {label}
    </button>
  )

  if (checking) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-[#0b1220] p-8 text-white">Checking access…</div>
      </>
    )
  }

  if (!allowed) return null

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-[#0b1220] px-4 py-8 text-white md:px-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <Link href="/admin" className="text-sm text-gray-400 hover:text-gray-200">
                ← Admin
              </Link>
              <h1 className="mt-2 text-2xl font-bold">Beta Testimonials</h1>
              <p className="mt-1 text-sm text-gray-400">
                Review beta feedback before it appears on the homepage.
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {filterBtn("all", statusFilter === "all", "All", () => setStatusFilter("all"))}
            {filterBtn("pending", statusFilter === "pending", "Pending", () =>
              setStatusFilter("pending")
            )}
            {filterBtn("approved", statusFilter === "approved", "Approved", () =>
              setStatusFilter("approved")
            )}
            {filterBtn("featured", statusFilter === "featured", "Featured", () =>
              setStatusFilter("featured")
            )}
          </div>

          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search title or review…"
            className="w-full max-w-md rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-white placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-400"
          />

          <p className="text-xs text-gray-500">
            Showing {rows.length} · {filteredCountLabel}
            {listLoading ? " · loading…" : ""}
          </p>

          <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,24rem)]">
            <div className="overflow-hidden rounded-xl border border-white/10 bg-white/5">
              {rows.length === 0 && !listLoading ? (
                <EmptyState title="No testimonials" description="Nothing matches this filter." />
              ) : (
                <ul className="divide-y divide-white/10">
                  {rows.map((row) => (
                    <li key={row.id}>
                      <button
                        type="button"
                        onClick={() => setSelected(row)}
                        className={`w-full px-4 py-4 text-left transition hover:bg-white/5 ${
                          selected?.id === row.id ? "bg-white/10" : ""
                        }`}
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="min-w-0">
                            <p className="font-medium text-white">{row.title}</p>
                            <p className="mt-1 text-sm text-gray-400">
                              {row.profiles?.username ?? "Unknown user"} ·{" "}
                              {new Date(row.created_at).toLocaleDateString()}
                            </p>
                            <p className="mt-2 text-sm text-gray-300">
                              {previewText(row.review)}
                            </p>
                          </div>
                          <span
                            className={`shrink-0 rounded px-2 py-0.5 text-xs font-medium ${statusBadgeClass(row)}`}
                          >
                            {statusLabel(row)}
                          </span>
                        </div>
                        <div className="mt-2">
                          <StarRatingDisplay rating={row.rating} className="text-sm" />
                        </div>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <aside className="rounded-xl border border-white/10 bg-white/5 p-5 lg:sticky lg:top-24 lg:self-start">
              {selected ? (
                <div className="space-y-4">
                  <div>
                    <p className="text-xs uppercase tracking-wide text-gray-500">Selected</p>
                    <h2 className="mt-1 text-lg font-semibold text-white">{selected.title}</h2>
                    <p className="mt-1 text-sm text-gray-400">
                      {selected.profiles?.username ?? "Unknown user"}
                    </p>
                    <div className="mt-2">
                      <StarRatingDisplay rating={selected.rating} />
                    </div>
                  </div>

                  <p className="whitespace-pre-wrap text-sm leading-relaxed text-gray-200">
                    {selected.review}
                  </p>

                  {selected.pros ? (
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">
                        Pros
                      </p>
                      <p className="mt-1 text-sm text-gray-300">{selected.pros}</p>
                    </div>
                  ) : null}

                  {selected.cons ? (
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">
                        Cons
                      </p>
                      <p className="mt-1 text-sm text-gray-300">{selected.cons}</p>
                    </div>
                  ) : null}

                  <p className="text-sm text-gray-400">
                    Recommend:{" "}
                    <span className="text-gray-200">
                      {selected.would_recommend ? "Yes" : "No"}
                    </span>
                  </p>

                  <div className="flex flex-col gap-2">
                    {!selected.approved ? (
                      <button
                        type="button"
                        disabled={savingDetail}
                        onClick={() => void handleApprove(selected)}
                        className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-500 disabled:opacity-60"
                      >
                        Approve
                      </button>
                    ) : (
                      <button
                        type="button"
                        disabled={savingDetail}
                        onClick={() => void handleReject(selected)}
                        className="rounded-lg border border-white/15 bg-white/5 px-4 py-2 text-sm font-semibold text-white hover:bg-white/10 disabled:opacity-60"
                      >
                        Reject
                      </button>
                    )}

                    <button
                      type="button"
                      disabled={savingDetail || !selected.approved}
                      onClick={() => void handleToggleFeatured(selected)}
                      className="rounded-lg border border-amber-400/30 bg-amber-500/15 px-4 py-2 text-sm font-semibold text-amber-100 hover:bg-amber-500/25 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      {selected.featured ? "Unfeature" : "Feature on Homepage"}
                    </button>

                    <button
                      type="button"
                      disabled={savingDetail}
                      onClick={() => void handleDelete(selected)}
                      className="rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm font-semibold text-red-200 hover:bg-red-500/20 disabled:opacity-60"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              ) : (
                <p className="text-sm text-gray-500">Select a testimonial to review.</p>
              )}
            </aside>
          </div>
        </div>
      </div>
    </>
  )
}
