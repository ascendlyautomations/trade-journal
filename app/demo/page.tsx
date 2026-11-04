"use client"

import { useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { isDemoUserId } from "@/lib/demo/constants"
import {
  enterGuestExplore,
  isShowcaseUserId,
  showcaseProfilePath,
} from "@/lib/guestExplore"
import { useUserProfile } from "@/lib/useUserProfile"

const FAILURE_MESSAGE =
  "Unable to load Explore as Guest. Please try again."

export default function DemoIndexPage() {
  const router = useRouter()
  const { user, loading } = useUserProfile()
  const [error, setError] = useState<string | null>(null)
  const startedRef = useRef(false)

  useEffect(() => {
    if (loading) return
    if (startedRef.current) return

    if (user && !isDemoUserId(user.id)) {
      if (isShowcaseUserId(user.id)) {
        router.replace(showcaseProfilePath())
        return
      }
      router.replace("/dashboard")
      return
    }

    startedRef.current = true

    void enterGuestExplore().then((result) => {
      if (result.ok) {
        window.location.assign(result.profileHref)
        return
      }
      setError(FAILURE_MESSAGE)
      startedRef.current = false
    })
  }, [loading, user, router])

  if (error) {
    return (
      <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4 px-4 text-center">
        <p className="max-w-md text-sm text-gray-400">{error}</p>
        <button
          type="button"
          className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-600"
          onClick={() => {
            setError(null)
            startedRef.current = false
          }}
        >
          Try again
        </button>
      </div>
    )
  }

  return null
}
