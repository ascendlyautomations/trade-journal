"use client"

import { useCallback, useMemo, useState } from "react"
import AchievementCard from "../components/AchievementCard"
import AchievementsPageDetailModal from "../components/AchievementsPageDetailModal"
import AchievementUploadModal, {
  type AchievementUploadInitialValues,
} from "../components/AchievementUploadModal"
import SystemMilestonesSection from "@/app/components/milestones/SystemMilestonesSection"
import { ConfirmModal, FeedbackModal, useDeleteAchievementConfirmation, useFeedbackPopup } from "../components/ui"
import { supabase } from "../../lib/supabaseClient"
import {
  type Achievement,
  ACHIEVEMENT_PAGE_MOBILE_FILTER_OPTIONS,
  ACHIEVEMENT_TYPE_FILTER_OPTIONS,
  achievementMatchesPageFilter,
  achievementPageMobileFilterActive,
  type AchievementPageFilter,
} from "../../lib/achievements"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useUserStreaks } from "@/lib/useUserStreaks"
import { useUserAchievements } from "@/lib/useUserAchievements"
import { patchUserAchievementsCache } from "@/lib/userAchievementsCache"
import { SkeletonAchievementsGrid } from "../components/ui/skeletons"
import EmptyState from "../components/ui/EmptyState"

export default function AchievementsPage() {
  const { user, profile, loading: profileLoading } = useUserProfile()
  const userId = user?.id ?? null
  const { snapshot: streakSnapshot, loading: streaksLoading } = useUserStreaks(
    userId,
    { onboardingCompleted: profile?.onboarding_completed }
  )
  const {
    achievements,
    loading,
    error,
    refresh: refreshAchievements,
  } = useUserAchievements(userId)
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 2500 })
  const [filter, setFilter] = useState<AchievementPageFilter>("all")
  const [showForm, setShowForm] = useState(false)
  const [editingAchievement, setEditingAchievement] = useState<Achievement | null>(
    null
  )
  const [createInitialValues, setCreateInitialValues] = useState<
    AchievementUploadInitialValues | undefined
  >(undefined)
  const [selectedAchievementDetail, setSelectedAchievementDetail] =
    useState<Achievement | null>(null)


  const authError =
    !profileLoading && !userId && !isDemoModeActive()
      ? "Please log in to view achievements."
      : null
  const displayError = authError ?? error
  const pageLoading = profileLoading || loading

  const filteredAchievements = useMemo(() => {
    return achievements.filter((a) => achievementMatchesPageFilter(a, filter))
  }, [achievements, filter])

  const featured = useMemo(
    () =>
      achievements.filter(
        (a) => a.is_featured && !achievementMatchesPageFilter(a, "milestones")
      ),
    [achievements]
  )

  const showMilestonesTab = filter === "milestones"

  const visible = filteredAchievements

  const unreadFeatured = featured.length

  function openCreate() {
    if (isDemoModeActive()) {
      requestDemoSignup("upload")
      return
    }
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
    if (userId) await refreshAchievements()
    showPopup({ type: "success", message: "Achievement saved" })
  }

  const handleDeleteAchievement = useCallback(
    async (achievementId: string) => {
      if (!userId) return
      if (isDemoModeActive()) {
        requestDemoSignup("delete")
        return
      }
      const { error: delErr } = await supabase
        .from("achievements")
        .delete()
        .eq("id", achievementId)
        .eq("user_id", userId)
      if (delErr) {
        console.error("[achievements] delete failed", delErr)
        throw delErr
      }
      patchUserAchievementsCache(userId, (prev) =>
        prev.filter((row) => row.id !== achievementId)
      )
    },
    [userId]
  )

  const { requestDelete, confirmModalProps } =
    useDeleteAchievementConfirmation(handleDeleteAchievement)

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-gray-100 sm:px-6">
        <div className="mx-auto max-w-6xl space-y-5">
          <div className="flex flex-col gap-3 rounded-xl border border-white/10 bg-white/5 p-5 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h1 className="text-2xl font-semibold text-blue-300">
                Achievements
              </h1>
              <p className="text-sm text-gray-300">
                Track payouts, passed evals, and trading milestones.
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

          {displayError ? (
            <div className="rounded-lg border border-red-400/30 bg-red-500/10 p-3 text-sm text-red-200">
              {displayError}
            </div>
          ) : null}

          {showMilestonesTab ? (
            <>
              <SystemMilestonesSection
                userId={userId}
                signals={streakSnapshot?.milestoneSignals}
                loading={profileLoading || streaksLoading}
              />
              {!pageLoading && visible.length > 0 ? (
                <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  {visible.map((a) => (
                    <AchievementCard
                      key={a.id}
                      achievement={a}
                      onOpenDetail={setSelectedAchievementDetail}
                      onEdit={() => openEdit(a)}
                      onDelete={() => requestDelete(a.id)}
                    />
                  ))}
                </section>
              ) : null}
            </>
          ) : null}

          {!showMilestonesTab && !pageLoading && featured.length > 0 ? (
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
                    onOpenDetail={setSelectedAchievementDetail}
                  />
                ))}
              </div>
            </section>
          ) : null}

          {showMilestonesTab ? null : pageLoading ? (
            <SkeletonAchievementsGrid count={6} />
          ) : visible.length === 0 ? (
            <EmptyState
              icon="🏆"
              title={
                achievements.length === 0
                  ? "No achievements yet"
                  : "No achievements match these filters"
              }
              description={
                achievements.length === 0
                  ? "Track payouts, passed evals, and milestone moments you want to remember."
                  : "Try another filter or add a new achievement."
              }
              action={
                achievements.length === 0 ? (
                  <button
                    type="button"
                    onClick={() => {
                      setEditingAchievement(null)
                      setCreateInitialValues(undefined)
                      setShowForm(true)
                    }}
                    className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
                  >
                    + Add Achievement
                  </button>
                ) : undefined
              }
              className="py-10"
            />
          ) : (
            <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {visible.map((a) => (
                <AchievementCard
                  key={a.id}
                  achievement={a}
                  onOpenDetail={setSelectedAchievementDetail}
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

      {selectedAchievementDetail ? (
        <AchievementsPageDetailModal
          achievement={selectedAchievementDetail}
          onClose={() => setSelectedAchievementDetail(null)}
          onEdit={() => {
            openEdit(selectedAchievementDetail)
            setSelectedAchievementDetail(null)
          }}
          onDelete={() => {
            requestDelete(selectedAchievementDetail.id)
            setSelectedAchievementDetail(null)
          }}
        />
      ) : null}

      <FeedbackModal {...feedbackModalProps} />
    </>
  )
}
