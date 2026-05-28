"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import Navbar from "../components/Navbar"
import AchievementCard from "../components/AchievementCard"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { formatDateOnly } from "@/lib/formatDate"
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
  payout_amount: string
  achieved_at: string
  image_url: string | null
  is_public: boolean
  is_featured: boolean
}

const EMPTY_FORM: AchievementFormState = {
  achievement_type: "payout",
  title: "",
  description: "",
  payout_amount: "",
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
  const [achievedDate, setAchievedDate] = useState<string | null>(null)
  const [showCalendar, setShowCalendar] = useState(false)
  const [calendarMonth, setCalendarMonth] = useState<Date>(() => {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), 1)
  })
  const [file, setFile] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [removeImage, setRemoveImage] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const calendarWrapperRef = useRef<HTMLDivElement | null>(null)

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

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      const target = e.target as Node
      if (!calendarWrapperRef.current?.contains(target)) {
        setShowCalendar(false)
      }
    }

    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  function openCreate() {
    setEditingId(null)
    setForm(EMPTY_FORM)
    setAchievedDate(null)
    setShowCalendar(false)
    const now = new Date()
    setCalendarMonth(new Date(now.getFullYear(), now.getMonth(), 1))
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
      payout_amount:
        a.value_numeric != null && Number.isFinite(Number(a.value_numeric))
          ? String(a.value_numeric)
          : "",
      achieved_at: a.achieved_at ? String(a.achieved_at).slice(0, 10) : "",
      image_url: a.image_url || null,
      is_public: !!a.is_public,
      is_featured: !!a.is_featured,
    })
    setAchievedDate(a.achieved_at ? String(a.achieved_at).slice(0, 10) : null)
    setShowCalendar(false)
    if (a.achieved_at) {
      const d = new Date(String(a.achieved_at))
      if (!Number.isNaN(d.getTime())) {
        setCalendarMonth(new Date(d.getFullYear(), d.getMonth(), 1))
      }
    }
    setFile(null)
    setPreviewUrl(null)
    setRemoveImage(false)
    setShowForm(true)
  }

  function openAchievedDateCalendar() {
    if (achievedDate) {
      const parsed = new Date(achievedDate)
      if (!Number.isNaN(parsed.getTime())) {
        setCalendarMonth(new Date(parsed.getFullYear(), parsed.getMonth(), 1))
      }
    }
    setShowCalendar(true)
  }

  const monthLabel = calendarMonth.toLocaleString(undefined, {
    month: "long",
    year: "numeric",
  })

  const monthStart = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth(), 1)
  const monthEnd = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + 1, 0)
  const startWeekday = monthStart.getDay()
  const totalDays = monthEnd.getDate()
  const cells: Array<number | null> = []
  for (let i = 0; i < startWeekday; i++) cells.push(null)
  for (let day = 1; day <= totalDays; day++) cells.push(day)
  while (cells.length % 7 !== 0) cells.push(null)

  async function saveAchievement() {
    if (!userId || !form.title.trim() || !form.achievement_type.trim()) return
    const normalizedType = normalizeAchievementType(form.achievement_type)
    const payoutAmount =
      normalizedType === "payout" ? Number(form.payout_amount) : null
    if (
      normalizedType === "payout" &&
      (!Number.isFinite(payoutAmount) || (payoutAmount as number) <= 0)
    ) {
      setError("Please enter a valid payout amount.")
      return
    }
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
      let uploadFile: File = file
      if (file.type?.startsWith("image/")) {
        uploadFile = await compressImage(file)
      }
      const uploadName = uploadFile.type?.startsWith("image/")
        ? uploadFile.name
        : `${safeBase || "image"}.${ext}`
      const filePath = `achievements/${userId}/${Date.now()}-${uploadName}`

      const { error: uploadErr } = await supabase.storage
        .from("screenshots")
        .upload(filePath, uploadFile, { upsert: true })
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
      achievement_type: normalizedType,
      title: form.title.trim(),
      description: form.description.trim() || null,
      badge_key: badgeKeyFromType(form.achievement_type),
      category: categoryFromType(form.achievement_type),
      tier: null,
      value_numeric: normalizedType === "payout" ? payoutAmount : null,
      value_text:
        normalizedType === "payout" && payoutAmount != null
          ? `+$${Math.abs(payoutAmount).toLocaleString(undefined, {
              minimumFractionDigits: 0,
              maximumFractionDigits: 2,
            })}`
          : null,
      currency: normalizedType === "payout" ? "USD" : null,
      account_type: null,
      account_name: null,
      account_size: null,
      mode: null,
      firm: null,
      achieved_at: achievedDate || form.achieved_at || null,
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
    setAchievedDate("")
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
              {normalizeAchievementType(form.achievement_type) === "payout" ? (
                <label className="text-xs text-gray-300">
                  Payout Amount (USD)
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={form.payout_amount}
                    onChange={(e) =>
                      setForm((prev) => ({ ...prev, payout_amount: e.target.value }))
                    }
                    placeholder="3500"
                    className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
                  />
                </label>
              ) : null}
              <label className="text-xs text-gray-300">
                Achieved Date
                <div ref={calendarWrapperRef} className="relative calendar-wrapper">
                  <div
                    className="mt-1.5 w-full px-3 py-2.5 rounded-lg bg-[#0f172a]/70 border border-white/10 text-white cursor-pointer flex items-center hover:border-blue-400 transition"
                    onClick={openAchievedDateCalendar}
                  >
                    <span
                      className={
                        achievedDate
                          ? "text-sm md:text-base font-medium text-white"
                          : "text-sm text-gray-400"
                      }
                    >
                      {achievedDate ? formatDateOnly(achievedDate) : "Select date"}
                    </span>
                  </div>

                  {showCalendar ? (
                    <div className="absolute left-0 top-full mt-2 z-50 rounded-xl border border-white/10 bg-[#0f172a] shadow-lg">
                      <div className="flex items-center justify-between gap-2 border-b border-white/10 px-3 py-2 text-sm text-white">
                        <button
                          type="button"
                          onClick={() =>
                            setCalendarMonth(
                              new Date(
                                calendarMonth.getFullYear(),
                                calendarMonth.getMonth() - 1,
                                1
                              )
                            )
                          }
                          className="rounded bg-white/10 px-2 py-1 hover:bg-white/20"
                        >
                          ←
                        </button>
                        <span>{monthLabel}</span>
                        <button
                          type="button"
                          onClick={() =>
                            setCalendarMonth(
                              new Date(
                                calendarMonth.getFullYear(),
                                calendarMonth.getMonth() + 1,
                                1
                              )
                            )
                          }
                          className="rounded bg-white/10 px-2 py-1 hover:bg-white/20"
                        >
                          →
                        </button>
                      </div>
                      <div className="grid grid-cols-7 gap-1 p-2 text-center text-xs text-gray-400">
                        {["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"].map((label) => (
                          <span key={label}>{label}</span>
                        ))}
                        {cells.map((day, i) => {
                          if (!day) return <span key={`empty-${i}`} className="h-8" />
                          const y = calendarMonth.getFullYear()
                          const m = String(calendarMonth.getMonth() + 1).padStart(2, "0")
                          const d = String(day).padStart(2, "0")
                          const dateValue = `${y}-${m}-${d}`
                          const isSelected = achievedDate === dateValue
                          return (
                            <button
                              key={dateValue}
                              type="button"
                              onClick={() => {
                                setAchievedDate(dateValue)
                                setForm((prev) => ({ ...prev, achieved_at: dateValue }))
                                setShowCalendar(false)
                              }}
                              className={`h-8 w-8 rounded ${
                                isSelected
                                  ? "bg-blue-500/30 text-blue-200"
                                  : "text-gray-200 hover:bg-white/10"
                              }`}
                            >
                              {day}
                            </button>
                          )
                        })}
                      </div>
                      <div className="mt-2 flex justify-between px-2 pb-2">
                        <button
                          type="button"
                          className="text-xs text-blue-400 hover:text-blue-300"
                          onClick={() => {
                            const today = new Date()
                            const y = today.getFullYear()
                            const m = String(today.getMonth() + 1).padStart(2, "0")
                            const d = String(today.getDate()).padStart(2, "0")
                            const dateValue = `${y}-${m}-${d}`
                            setAchievedDate(dateValue)
                            setForm((prev) => ({ ...prev, achieved_at: dateValue }))
                            setCalendarMonth(new Date(today.getFullYear(), today.getMonth(), 1))
                            setShowCalendar(false)
                          }}
                        >
                          Today
                        </button>
                        <button
                          type="button"
                          className="text-xs text-gray-400 hover:text-white"
                          onClick={() => {
                            setAchievedDate(null)
                            setForm((prev) => ({ ...prev, achieved_at: "" }))
                            setShowCalendar(false)
                          }}
                        >
                          Clear
                        </button>
                      </div>
                    </div>
                  ) : null}
                </div>
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
