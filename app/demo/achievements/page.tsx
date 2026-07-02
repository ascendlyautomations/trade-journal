"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoAchievementsRedirectPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace("/achievements")
  }, [router])

  return null
}
