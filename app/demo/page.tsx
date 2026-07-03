"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { isDemoUserId } from "@/lib/demo/constants"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoIndexPage() {
  const router = useRouter()

  useEffect(() => {
    let cancelled = false

    async function enterDemo() {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (cancelled) return

      if (user && !isDemoUserId(user.id)) {
        router.replace("/dashboard")
        return
      }

      enableDemoMode()
      router.replace("/dashboard")
    }

    void enterDemo()

    return () => {
      cancelled = true
    }
  }, [router])

  return null
}
