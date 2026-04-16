"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import Navbar from "../components/Navbar"
import AchievementCard from "../components/AchievementCard"
import { supabase } from "../../lib/supabaseClient"
import {
  type Achievement,
  badgeKeyFromType,
  categoryFromType,
  fetchOwnAchievements,
  normalizeAchievementType,
} from "../../lib/achievements"

type CategoryFilter = "all" | "payouts" | "passed_evals" | "milestones"

type AchievementFormState = {
  achievement_type: string
  title: string
  description: string
  achieved_at: string
  image_url: string | null
  is_public: boolean
  is_featured: boolean
}

const EMPTY_FORM: AchievementFormState = {
  achievement_type: "payout",
  title: "",
  description: "",
  achieved_at: "",
  image_url: null,
  is_public: true,
  is_featured: false,
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
  const [file, setFile] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [removeImage, setRemoveImage] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)

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

  useEffect(() => {
    if (!file) {
      setPreviewUrl(null)
      return
    }
    const nextPreviewUrl = URL.createObjectURL(file)
    setPreviewUrl(nextPreviewUrl)
    return () => URL.revokeObjectURL(nextPreviewUrl)
  }, [file])

  function openCreate() {
    setEditingId(null)
    setForm(EMPTY_FORM)
    setFile(null)
    setPreviewUrl(null)
    setRemoveImage(false)
    setShowForm(true)
  }

  function openEdit(a: Achievement) {
    setEditingId(a.id)
    setForm({
      achievement_type: normalizeAchievementType(a.achievement_type),
      title: a.title || "",
      description: a.description || "",
      achieved_at: a.achieved_at ? String(a.achieved_at).slice(0, 10) : "",
      image_url: a.image_url || null,
      is_public: !!a.is_public,
      is_featured: !!a.is_featured,
    })
    setFile(null)
    setPreviewUrl(null)
    setRemoveImage(false)
    setShowForm(true)
  }

  async function saveAchievement() {
    if (!userId || !form.title.trim() || !form.achievement_type.trim()) return
    setBusy(true)
    setError(null)

    let imageUrl = form.image_url
    if (removeImage) {
      imageUrl = null
    }

    if (file) {
      const ext = file.name.includes(".")
        ? file.name.split(".").pop()?.toLowerCase() || "jpg"
        : "bin"
      const safeBase = file.name
        .replace(/\.[^/.]+$/, "")
        .toLowerCase()
        .replace(/[^a-z0-9-_]+/g, "-")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "")
      const filePath = `achievements/${userId}/${Date.now()}-${safeBase || "image"}.${ext}`

      const { error: uploadErr } = await supabase.storage
        .from("screenshots")
        .upload(filePath, file, { upsert: true })
      if (uploadErr) {
        setBusy(false)
        setError(uploadErr.message || "Could not upload image.")
        return
      }

      const { data: publicData } = supabase.storage.from("screenshots").getPublicUrl(filePath)
      imageUrl = publicData.publicUrl
    }

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
      image_url: imageUrl,
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
    setFile(null)
    setPreviewUrl(null)
    setRemoveImage(false)
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
                  <AchievementCard
                    key={a.id}
                    achievement={a}
                    featured
                    showVisibility={false}
                  />
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
                <AchievementCard
                  key={a.id}
                  achievement={a}
                  onEdit={() => openEdit(a)}
                  onDelete={() => void deleteAchievement(a.id)}
                />
              ))}
            </section>
          )}
        </div>
      </div>

      {showForm ? (
        <div
          className="fixed inset-0 z-[100] flex items-end justify-center bg-black/75 p-2 backdrop-blur-md sm:items-center sm:p-4"
          onClick={() => {
            setShowForm(false)
            setFile(null)
            setPreviewUrl(null)
            setRemoveImage(false)
          }}
        >
          <div
            className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] p-4 shadow-2xl shadow-blue-900/20 sm:p-6"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
            aria-label={editingId ? "Edit Achievement" : "Add Achievement"}
          >
            <div className="mb-3 border-b border-white/10 pb-3">
              <h2 className="text-xl font-semibold tracking-tight text-white">
                {editingId ? "Edit Achievement" : "Add Achievement"}
              </h2>
              <p className="mt-0.5 text-sm text-slate-300">
                Capture your achievements with a quick summary and image. 
              </p>
            </div>

            <div className="grid gap-2 sm:grid-cols-2 sm:gap-3">
              <label className="text-xs text-gray-300">
                Achievement Type
                <select
                  value={form.achievement_type}
                  onChange={(e) =>
                    setForm((prev) => ({ ...prev, achievement_type: e.target.value }))
                  }
                  className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
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
                  placeholder="e.g. First payout from Apex"
                  className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
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
                  className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-base text-white [color-scheme:dark] outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20 sm:text-sm"
                />
              </label>
              <label className="text-xs text-gray-300">
                Upload Image
                <div className="mt-1.5 rounded-lg border border-white/15 bg-[#0a1329] p-2.5">
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept="image/*"
                    onChange={(e) => {
                      const selected = e.target.files?.[0] ?? null
                      setFile(selected)
                      if (selected) setRemoveImage(false)
                    }}
                    className="hidden"
                  />
                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    className="h-9 rounded-md border border-blue-300/30 bg-blue-500/15 px-3 text-sm font-medium text-blue-100 transition hover:bg-blue-500/25"
                  >
                    {file ? "Change image" : "Choose image"}
                  </button>
                  <input
                    type="text"
                    readOnly
                    value={file?.name || ""}
                    placeholder="No image selected"
                    className="mt-2 w-full rounded-md border border-white/10 bg-[#0b1220] px-2 py-1.5 text-xs text-slate-300"
                  />
                  {previewUrl ? (
                    <img
                      src={previewUrl}
                      alt="Selected preview"
                      className="mt-2 max-h-40 w-full rounded-md border border-white/10 object-cover"
                    />
                  ) : form.image_url && !removeImage ? (
                    <div className="mt-2 space-y-2">
                      <img
                        src={form.image_url}
                        alt="Current achievement image"
                        className="max-h-40 w-full rounded-md border border-white/10 object-cover"
                      />
                      <button
                        type="button"
                        onClick={() => setRemoveImage(true)}
                        className="rounded border border-red-400/40 px-2 py-0.5 text-[11px] text-red-300 hover:bg-red-500/10"
                      >
                        Remove image
                      </button>
                    </div>
                  ) : removeImage ? (
                    <p className="mt-2 text-xs text-amber-300">
                      Image will be removed when you save.
                    </p>
                  ) : null}
                </div>
              </label>

              <label className="sm:col-span-2 text-xs text-gray-300">
                Description
                <textarea
                  rows={4}
                  value={form.description}
                  onChange={(e) => setForm((prev) => ({ ...prev, description: e.target.value }))}
                  placeholder="What happened and why it matters..."
                  className="mt-1.5 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 py-2.5 text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
                />
              </label>

              <div className="sm:col-span-2 mt-1 flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-3 py-2.5">
                <p className="text-sm text-slate-200">Visibility</p>
                <label className="inline-flex items-center gap-2 text-sm text-gray-100">
                  <input
                    type="checkbox"
                    checked={form.is_public}
                    onChange={(e) => setForm((prev) => ({ ...prev, is_public: e.target.checked }))}
                    className="h-4 w-4 rounded border-white/20 bg-[#0b1220] accent-blue-500"
                  />
                  Public
                </label>
              </div>
            </div>

            <div className="mt-5 flex flex-col-reverse gap-2 border-t border-white/10 pt-4 sm:flex-row sm:justify-end">
              <button
                type="button"
                onClick={() => {
                  setShowForm(false)
                  setFile(null)
                  setPreviewUrl(null)
                  setRemoveImage(false)
                }}
                className="h-10 rounded-lg border border-white/20 bg-white/5 px-4 text-sm font-medium text-slate-200 transition hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => void saveAchievement()}
                disabled={busy}
                className="h-10 rounded-lg bg-gradient-to-r from-blue-500 to-emerald-500 px-4 text-sm font-semibold text-white transition hover:from-blue-400 hover:to-emerald-400 disabled:opacity-60"
              >
                {busy ? "Saving..." : editingId ? "Update Achievement" : "Save Achievement"}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  )
}
