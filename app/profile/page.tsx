"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { SkeletonProfilePage } from "@/app/components/ui/skeletons"
import { DEMO_PROFILE_PATH } from "@/lib/demo/constants"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { signedInProfileHref } from "@/lib/profileRoutes"
import { useUserProfile } from "@/lib/UserProfileProvider"

/** Phone Profile tab (and bookmarks) hit `/profile`. Send them to the signed-in user. */
export default function ProfileIndexPage() {
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()

  useEffect(() => {
    if (isDemoModeActive()) {
      router.replace(
        profile ? signedInProfileHref(profile, user?.id) : DEMO_PROFILE_PATH
      )
      return
    }
    if (loading) return
    const href = signedInProfileHref(profile, user?.id)
    if (href === "/profile") {
      router.replace("/login")
      return
    }
    router.replace(href)
  }, [loading, profile, router, user?.id])

  return <SkeletonProfilePage />
}
