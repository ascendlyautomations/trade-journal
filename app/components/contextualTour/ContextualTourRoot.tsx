"use client"

import { useMemo, type ReactNode } from "react"
import { usePathname } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { isStandaloneFlowRoute } from "@/lib/authRoutes"
import { pathnameMatchesTourSurface } from "@/lib/contextualTour/routes"
import {
  ContextualTourProvider,
  useContextualTourPostOnboardingInvite,
} from "@/lib/contextualTour/ContextualTourProvider"
import ContextualTourOverlay from "./ContextualTourOverlay"
import ContextualTourInviteOverlay from "./ContextualTourInviteOverlay"

function ContextualTourPostOnboardingGate({
  enabled,
  userId,
  onDashboard,
}: {
  enabled: boolean
  userId: string
  onDashboard: boolean
}) {
  useContextualTourPostOnboardingInvite({ enabled, userId, onDashboard })
  return null
}

export default function ContextualTourRoot({ children }: { children: ReactNode }) {
  const pathname = usePathname() ?? ""
  const { user, profile, loading } = useUserProfile()
  const isNativeIos = useIsNativeIos()

  const onDashboard = useMemo(
    () =>
      user?.id
        ? pathnameMatchesTourSurface(pathname, "dashboard", user.id)
        : false,
    [pathname, user?.id]
  )

  const inviteEligible = useMemo(() => {
    if (isNativeIos) return false
    if (loading || !user?.id) return false
    if (profile?.is_banned) return false
    if (isStandaloneFlowRoute(pathname)) return false
    if (!profile?.onboarding_completed) return false
    return true
  }, [isNativeIos, loading, pathname, profile, user?.id])

  if (!user?.id) {
    return <>{children}</>
  }

  return (
    <ContextualTourProvider userId={user.id}>
      {children}
      {!isNativeIos ? (
        <>
          {inviteEligible ? (
            <ContextualTourPostOnboardingGate
              enabled={inviteEligible}
              userId={user.id}
              onDashboard={onDashboard}
            />
          ) : null}
          <ContextualTourInviteOverlay />
          <ContextualTourOverlay />
        </>
      ) : null}
    </ContextualTourProvider>
  )
}
