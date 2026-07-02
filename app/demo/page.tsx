"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoIndexPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace("/dashboard")
  }, [router])

  return null
}
