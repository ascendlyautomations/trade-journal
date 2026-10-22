"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"

/** Legacy route — promotional enrollment runs on `/onboarding`. */
export default function EarlyAccessWelcomePage() {
  const router = useRouter()

  useEffect(() => {
    router.replace("/onboarding")
  }, [router])

  return (
    <main className="flex min-h-screen items-center justify-center px-4 text-sm text-gray-300">
      Continuing…
    </main>
  )
}
