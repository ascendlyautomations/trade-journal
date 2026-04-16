"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import Navbar from "../components/Navbar"
import { supabase } from "../../lib/supabaseClient"
import {
  type Achievement,
  badgeIconForKey,
  badgeKeyFromType,
  categoryFromType,
  fetchOwnAchievements,
  formatAchievementDate,
  formatAchievementValue,
  normalizeAchievementType,
  tierClassName,
} from "../../lib/achievements"

type CategoryFilter = "all" | "payouts" | "passed_evals" | "milestones"

type AchievementFormState = {
  achievement_type: string
  title: string
  description: string
  achieved_at: string
  is_public: boolean
  is_featured: boolean
}

const EMPTY_FORM: AchievementFormState = {
  achievement_type: "payout",
  title: "",
  description: "",
  achieved_at: "",
  is_public: true,
  is_featured: false,
}

function cardSubtitle(a: Achievement): string {
  const parts = [a.firm, a.account_type, a.account_size].filter(
    (v) => v && String(v).trim() !== ""
  )
  return parts.length ? parts.join(" • ") : "Trading achievement"
}

export default function AchievementsPage() {
  const [userId, setUserId] = useState<string | null>(null)
  const [achievements, setAchievements] = useState<Achievement[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<CategoryFilter>("all")
  const [showForm, setShowForm] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [form, setForm] = useState<AchievementFormState>(EMPTY_FORM)

  const loadAchievements = useCallback(async (uid: string) => {
    setLoading(true)
    setError(null)
    const { data, error: fetchErr } = await fetchOwnAchievements(uid)
    if (fetchErr) {
      console.error("[achievements] fetch failed", fetchErr)
      setAchievements([])
      setError(fetchErr.message || "Could not load achievements.")
      setLoading(false)
      return
    }
    setAchievements((data || []) as Achievement[])
    setLoading(false)
  }, [])

  useEffect(() => {
    let cancelled = false
    async function init() {
      const { data, error: authError } = await supabase.auth.getUser()
      if (cancelled) return
      if (authError || !data?.user) {
        setError("Please log in to view achievements.")
        setLoading(false)
        return
      }
      setUserId(data.user.id)
      void loadAchievements(data.user.id)
    }
    void init()
    return () => {
      cancelled = true
    }
  }, [loadAchievements])

  const featured = useMemo(
    () => achievements.filter((a) => a.is_featured),
    [achievements]
  )

  const visible = useMemo(() => {
    if (filter === "all") return achievements
    return achievements.filter((a) => {
      const normalizedStored = String(a.category || "").toLowerCase().trim()
      const derived = categoryFromType(a.achievement_type)
      return normalizedStored === filter || derived === filter
    })
  }, [achievements, filter])

  const unreadFeatured = featured.length

  function openCreate() {
    setEditingId(null)
    setForm(EMPTY_FORM)
    setShowForm(true)
  }

  function openEdit(a: Achievement) {
    setEditingId(a.id)
    setForm({
      achievement_type: normalizeAchievementType(a.achievement_type),
      title: a.title || "",
      description: a.description || "",
      achieved_at: a.achieved_at ? String(a.achieved_at).slice(0, 10) : "",
      is_public: !!a.is_public,
      is_featured: !!a.is_featured,
    })
    setShowForm(true)
  }

  async function saveAchievement() {
    if (!userId || !form.title.trim() || !form.achievement_type.trim()) return
    setBusy(true)
    const payload = {
      user_id: userId,
      achievement_type: normalizeAchievementType(form.achievement_type),
      title: form.title.trim(),
      description: form.description.trim() || null,
      badge_key: badgeKeyFromType(form.achievement_type),
      category: categoryFromType(form.achievement_type),
      tier: null,
      value_numeric: null,
      value_text: null,
      account_type: null,
      account_name: null,
      account_size: null,
      mode: null,
      firm: null,
      achieved_at: form.achieved_at || null,
      is_public: form.is_public,
      is_featured: form.is_featured,
    }

    const query = editingId
      ? supabase.from("achievements").update(payload).eq("id", editingId).eq("user_id", userId)
      : supabase.from("achievements").insert(payload)

    const { error: saveErr } = await query
    setBusy(false)
    if (saveErr) {
      console.error("[achievements] save failed", saveErr)
      setError(saveErr.message || "Could not save achievement.")
      return
    }
    setShowForm(false)
    setForm(EMPTY_FORM)
    setEditingId(null)
    await loadAchievements(userId)
  }

  async function deleteAchievement(id: string) {
    if (!userId) return
    if (!window.confirm("Delete this achievement?")) return
    const { error: delErr } = await supabase
      .from("achievements")
      .delete()
      .eq("id", id)
      .eq("user_id", userId)
    if (delErr) {
      console.error("[achievements] delete failed", delErr)
      setError(delErr.message || "Could not delete achievement.")
      return
    }
    setAchievements((prev) => prev.filter((a) => a.id !== id))
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-gray-100 sm:px-6">
        <div className="mx-auto max-w-6xl space-y-5">
          <div className="flex flex-col gap-3 rounded-xl border border-white/10 bg-white/5 p-5 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h1 className="text-2xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
                Achievements
              </h1>
              <p className="text-sm text-gray-300">
                Track payouts, milestones, and consistency wins.
              </p>
            </div>
            <button
              type="button"
              onClick={openCreate}
              className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
            >
              + Add Achievement
            </button>
          </div>

          <div className="flex flex-wrap gap-2">
            {(["all", "payouts", "passed_evals", "milestones"] as const).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => setFilter(key)}
                className={`rounded-lg border px-3 py-1.5 text-sm ${
                  filter === key
                    ? "border-blue-400/60 bg-blue-500/20 text-white"
                    : "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10"
                }`}
              >
                {key === "all"
                  ? "All"
                  : key === "passed_evals"
                  ? "Passed Evals"
                  : key[0].toUpperCase() + key.slice(1)}
              </button>
            ))}
          </div>

          {error ? (
            <div className="rounded-lg border border-red-400/30 bg-red-500/10 p-3 text-sm text-red-200">
              {error}
            </div>
          ) : null}

          {!loading && featured.length > 0 ? (
            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold text-white">Featured</h2>
                <span className="text-xs text-gray-400">{unreadFeatured} highlighted</span>
              </div>
              <div className="grid gap-3 md:grid-cols-2">
                {featured.map((a) => (
                  <article
                    key={a.id}
                    className={`rounded-xl border p-4 ${tierClassName(a.tier ?? null)}`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-lg">
                          {badgeIconForKey(a.badge_key, a.achievement_type)}
                        </p>
                        <h3 className="text-sm font-semibold text-white">{a.title}</h3>
                        <p className="text-xs text-gray-300">{a.description || cardSubtitle(a)}</p>
                      </div>
                      <p className="text-[11px] uppercase text-gray-400">
                        {String(a.tier || "standard")}
                      </p>
                    </div>
                    <p className="mt-2 text-xs text-gray-300">
                      {formatAchievementValue(a) || "Achievement unlocked"}
                    </p>
                    <p className="mt-1 text-[11px] text-gray-400">
                      Achieved {formatAchievementDate(a.achieved_at)}
                    </p>
                  </article>
                ))}
              </div>
            </section>
          ) : null}

          {loading ? (
            <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center text-gray-300">
              Loading achievements...
            </div>
          ) : visible.length === 0 ? (
            <div className="rounded-xl border border-white/10 bg-white/5 p-8 text-center">
              <p className="text-base text-white">No achievements yet.</p>
              <p className="mt-2 text-sm text-gray-400">
                Add milestones like first payout, passed eval, profit targets, or consistency streaks.
              </p>
            </div>
          ) : (
            <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {visible.map((a) => (
                <article
                  key={a.id}
                  className={`rounded-xl border p-4 ${tierClassName(a.tier ?? null)}`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-lg">
                        {badgeIconForKey(a.badge_key, a.achievement_type)}
                      </p>
                      <h3 className="truncate text-sm font-semibold text-white">{a.title}</h3>
                    </div>
                    <span className="text-[10px] uppercase text-gray-400">
                      {String(a.tier || "standard")}
                    </span>
                  </div>
                  <p className="mt-1 text-xs text-gray-300">
                    {a.description || "Achievement unlocked"}
                  </p>
                  <p className="mt-1 text-xs text-gray-400">{cardSubtitle(a)}</p>
                  {formatAchievementValue(a) ? (
                    <p className="mt-1 text-xs text-emerald-300">
                      {formatAchievementValue(a)}
                    </p>
                  ) : null}
                  <p className="mt-1 text-[11px] text-gray-400">
                    {formatAchievementDate(a.achieved_at)} • {a.is_public ? "Public" : "Private"}
                  </p>
                  <div className="mt-3 flex gap-2">
                    <button
                      type="button"
                      onClick={() => openEdit(a)}
                      className="rounded-md border border-white/20 px-2 py-1 text-xs hover:bg-white/10"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      onClick={() => void deleteAchievement(a.id)}
                      className="rounded-md border border-red-400/40 px-2 py-1 text-xs text-red-300 hover:bg-red-500/10"
                    >
                      Delete
                    </button>
                  </div>
                </article>
              ))}
            </section>
          )}
        </div>
      </div>

      {showForm ? (
        <div
          className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 p-4"
          onClick={() => setShowForm(false)}
        >
          <div
            className="w-full max-w-2xl rounded-xl border border-white/10 bg-[#0f172a] p-4"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-3 text-lg font-semibold text-white">
              {editingId ? "Edit Achievement" : "Add Achievement"}
            </h2>
            <div className="grid gap-2 sm:grid-cols-2">
              <label className="text-xs text-gray-300">
                Achievement Type
                <select
                  value={form.achievement_type}
                  onChange={(e) =>
                    setForm((prev) => ({ ...prev, achievement_type: e.target.value }))
                  }
                  className="mt-1 w-full rounded-md border border-white/10 bg-[#020617] px-2 py-1.5 text-sm text-white"
                >
                  <option value="payout">Payout</option>
                  <option value="passed_eval">Passed Eval</option>
                  <option value="milestone">Milestone</option>
                </select>
              </label>
              <label className="text-xs text-gray-300">
                Title
                <input
                  type="text"
                  value={form.title}
                  onChange={(e) => setForm((prev) => ({ ...prev, title: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-white/10 bg-[#020617] px-2 py-1.5 text-sm text-white"
                />
              </label>
              <label className="text-xs text-gray-300">
                Achieved Date
                <input
                  type="date"
                  value={form.achieved_at}
                  onChange={(e) =>
                    setForm((prev) => ({ ...prev, achieved_at: e.target.value }))
                  }
                  className="mt-1 w-full rounded-md border border-white/10 bg-[#020617] px-2 py-1.5 text-sm text-white"
                />
              </label>
              <label className="sm:col-span-2 text-xs text-gray-300">
                Description
                <textarea
                  rows={3}
                  value={form.description}
                  onChange={(e) => setForm((prev) => ({ ...prev, description: e.target.value }))}
                  className="mt-1 w-full rounded-md border border-white/10 bg-[#020617] px-2 py-1.5 text-sm text-white"
                />
              </label>
              <label className="inline-flex items-center gap-2 text-sm text-gray-200">
                <input
                  type="checkbox"
                  checked={form.is_public}
                  onChange={(e) => setForm((prev) => ({ ...prev, is_public: e.target.checked }))}
                />
                Public
              </label>
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setShowForm(false)}
                className="rounded-md border border-white/20 px-3 py-1.5 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => void saveAchievement()}
                disabled={busy}
                className="rounded-md bg-blue-500 px-3 py-1.5 text-sm text-white disabled:opacity-60"
              >
                {busy ? "Saving..." : "Save"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
