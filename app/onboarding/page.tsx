"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import ProfileOnboarding from "@/app/components/ProfileOnboarding"
import { useUserProfile } from "@/lib/useUserProfile"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"

export default function OnboardingPage() {
  const router = useRouter()
  const { user, profile, loading, setProfile, refreshProfile } = useUserProfile()

  useEffect(() => {
    if (!loading && !user) {
      router.replace("/login")
    }
  }, [loading, user, router])

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
        Loading…
      </div>
    )
  }

  if (!user) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
        Redirecting to sign in…
      </div>
    )
  }

  return (
    <ProfileOnboarding
      userId={user.id}
      initialUsername={profile?.username}
      initialName={null}
      initialBio={profile?.bio}
      initialTradingStyle={profile?.trading_style}
      initialTraderType={profile?.trader_type}
      initialPrimaryMarket={profile?.primary_market}
      initialStartedTrading={profile?.started_trading}
      initialAvatarUrl={profile?.avatar_url}
      onComplete={(patch) => {
        setProfile((p) => (p ? { ...p, ...patch } : p))
        notifyGettingStartedChecklistMaybeCompleted()
        void refreshProfile()
        router.replace("/dashboard")
        router.refresh()
      }}
    />
  )
}
