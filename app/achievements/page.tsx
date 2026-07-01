"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import Navbar from "../components/Navbar"
import AchievementCard from "../components/AchievementCard"
import AchievementUploadModal, {
  type AchievementUploadInitialValues,
} from "../components/AchievementUploadModal"
import { ConfirmModal, useDeleteAchievementConfirmation } from "../components/ui"
import { supabase } from "../../lib/supabaseClient"
import {
  type Achievement,
  ACHIEVEMENT_PAGE_MOBILE_FILTER_OPTIONS,
  ACHIEVEMENT_TYPE_FILTER_OPTIONS,
  achievementMatchesPageFilter,
  achievementPageMobileFilterActive,
  type AchievementPageFilter,
  fetchOwnAchievements,
} from "../../lib/achievements"

export default function AchievementsPage() {
  const [userId, setUserId] = useState<string | null>(null)
  const [achievements, setAchievements] = useState<Achievement[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<AchievementPageFilter>("all")
  const [showForm, setShowForm] = useState(false)
  const [editingAchievement, setEditingAchievement] = useState<Achievement | null>(
    null
  )
  const [createInitialValues, setCreateInitialValues] = useState<
    AchievementUploadInitialValues | undefined
  >(undefined)

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

  const filteredAchievements = useMemo(() => {
    return achievements.filter((a) => achievementMatchesPageFilter(a, filter))
  }, [achievements, filter])

  const featured = useMemo(
    () => achievements.filter((a) => a.is_featured),
    [achievements]
  )

  const visible = filteredAchievements

  const unreadFeatured = featured.length

  function openCreate() {
    setEditingAchievement(null)
    setCreateInitialValues(undefined)
    setShowForm(true)
  }

  function openEdit(a: Achievement) {
    setEditingAchievement(a)
    setCreateInitialValues(undefined)
    setShowForm(true)
  }

  async function handleSaved() {
    if (userId) await loadAchievements(userId)
  }

  const handleDeleteAchievement = useCallback(
    async (achievementId: string) => {
      if (!userId) return
      const { error: delErr } = await supabase
        .from("achievements")
        .delete()
        .eq("id", achievementId)
        .eq("user_id", userId)
      if (delErr) {
        console.error("[achievements] delete failed", delErr)
        setError(delErr.message || "Could not delete achievement.")
        throw delErr
      }
      setAchievements((prev) => prev.filter((row) => row.id !== achievementId))
    },
    [userId]
  )

  const { requestDelete, confirmModalProps } =
    useDeleteAchievementConfirmation(handleDeleteAchievement)

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

          <div className="flex flex-nowrap gap-1.5 md:flex-wrap md:gap-2">
            {ACHIEVEMENT_TYPE_FILTER_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => setFilter(option.value)}
                className={`hidden rounded-lg border px-3 py-1.5 text-sm md:inline-flex ${
                  filter === option.value
                    ? "border-blue-400/60 bg-blue-500/20 text-white"
                    : "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10"
                }`}
              >
                {option.label}
              </button>
            ))}
            {ACHIEVEMENT_PAGE_MOBILE_FILTER_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => setFilter(option.value)}
                className={`min-w-0 flex-1 basis-0 rounded-lg border px-2 py-1.5 text-center text-xs whitespace-nowrap md:hidden ${
                  achievementPageMobileFilterActive(filter, option.value)
                    ? "border-blue-400/60 bg-blue-500/20 text-white"
                    : "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10"
                }`}
              >
                {option.label}
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
              <p className="text-base text-white">
                {achievements.length === 0
                  ? "No achievements yet."
                  : "No achievements match these filters."}
              </p>
              <p className="mt-2 text-sm text-gray-400">
                {achievements.length === 0
                  ? "Add milestones like first payout, passed eval, profit targets, or consistency streaks."
                  : "Try another filter or add a new achievement."}
              </p>
            </div>
          ) : (
            <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {visible.map((a) => (
                <AchievementCard
                  key={a.id}
                  achievement={a}
                  onEdit={() => openEdit(a)}
                  onDelete={() => requestDelete(a.id)}
                />
              ))}
            </section>
          )}
        </div>
      </div>

      <AchievementUploadModal
        open={showForm}
        onClose={() => {
          setShowForm(false)
          setEditingAchievement(null)
          setCreateInitialValues(undefined)
        }}
        userId={userId}
        onSaved={handleSaved}
        initialValues={createInitialValues}
        editingAchievement={editingAchievement}
      />

      <ConfirmModal {...confirmModalProps} />
    </>
  )
}
