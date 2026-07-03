"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { isDemoUserId } from "@/lib/demo/constants"
import { enableDemoMode } from "@/lib/demo/demoMode"
import { useUserProfile } from "@/lib/useUserProfile"

export default function DemoIndexPage() {
  const router = useRouter()
  const { user, loading } = useUserProfile()

  useEffect(() => {
    if (loading) return

    if (user && !isDemoUserId(user.id)) {
      router.replace("/dashboard")
      return
    }

    enableDemoMode()
    router.replace("/dashboard")
  }, [loading, user, router])

  return null
}
