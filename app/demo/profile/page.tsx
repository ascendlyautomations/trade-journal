"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"
import { DEMO_PROFILE_PATH } from "@/lib/demo/constants"

export default function DemoProfileRedirectPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace(DEMO_PROFILE_PATH)
  }, [router])

  return null
}
