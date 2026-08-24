"use client"

import StreakCard from "@/app/components/streaks/StreakCard"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useUserStreaks } from "@/lib/useUserStreaks"

export default function StreaksPage() {
  useScrollPageTopOnMount()
  const { user, profile, loading: profileLoading } = useUserProfile()
  const { snapshot, loading: streaksLoading } = useUserStreaks(user?.id, {
    onboardingCompleted: profile?.onboarding_completed,
  })

  const loading = profileLoading || streaksLoading

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-gray-100 sm:px-6">
        <div className="mx-auto max-w-6xl space-y-6">
          <header className="rounded-xl border border-white/10 bg-white/5 p-5 md:p-6">
            <h1 className="text-2xl font-semibold text-blue-300 md:text-3xl">
              Streaks
            </h1>
            <p className="mt-2 max-w-3xl text-sm leading-relaxed text-gray-300 md:text-base">
              Build consistency one day at a time. Track your trading habits and
              maintain your momentum.
            </p>
          </header>

          {!user && !profileLoading ? (
            <div className="rounded-xl border border-white/10 bg-white/5 p-8 text-center text-gray-300">
              Please log in to view your streaks.
            </div>
          ) : (
            <div className="grid gap-5 lg:grid-cols-3 lg:gap-6">
              <StreakCard
                icon="📓"
                title="Trading Journal Streak"
                description="Log at least one trade each weekday. Weekends never break your streak."
                stats={
                  snapshot?.journal ?? {
                    current: 0,
                    longest: 0,
                    nextMilestone: 3,
                    progressRatio: 0,
                    unitLabel: "Days",
                  }
                }
                loading={loading}
              />
              <StreakCard
                icon="📣"
                title="Posting Streak"
                description="Share at least one public trade, post, or clip each weekday. Weekends are free."
                stats={
                  snapshot?.posting ?? {
                    current: 0,
                    longest: 0,
                    nextMilestone: 3,
                    progressRatio: 0,
                    unitLabel: "Days",
                  }
                }
                loading={loading}
              />
              <StreakCard
                icon="🏆"
                title="Winning Streak"
                description="Consecutive winning trades. Break-even trades do not reset your streak."
                stats={
                  snapshot?.winning ?? {
                    current: 0,
                    longest: 0,
                    nextMilestone: 5,
                    progressRatio: 0,
                    unitLabel: "Wins",
                  }
                }
                loading={loading}
              />
            </div>
          )}
        </div>
      </div>
    </>
  )
}
