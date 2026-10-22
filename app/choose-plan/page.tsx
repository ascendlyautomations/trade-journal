"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import { resolvePostAuthAppPath } from "@/lib/subscriptionAccess"
import { getPendingCreatorCode, buildCreatorSignupPath } from "@/lib/creatorAccess"

/** Legacy route — standard signup no longer stops here; send users forward. */
export default function ChoosePlanPage() {
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()

  useEffect(() => {
    if (loading) return
    if (!user) {
      const pendingCreatorCode = getPendingCreatorCode()
      router.replace(
        pendingCreatorCode
          ? buildCreatorSignupPath(pendingCreatorCode)
          : "/login?tab=signup"
      )
      return
    }
    if (!profile) return

    router.replace(
      profileNeedsOnboarding(profile)
        ? "/onboarding"
        : resolvePostAuthAppPath(profile)
    )
  }, [loading, user, profile, router])

  return (
    <div className="flex min-h-screen items-center justify-center px-4 text-gray-300">
      Continuing…
    </div>
  )
}
