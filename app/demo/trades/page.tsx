"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoTradesRedirectPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace("/trades")
  }, [router])

  return null
}
