"use client"

import Link from "next/link"
import { useParams } from "next/navigation"
import CheckInDayDetail from "@/app/components/psychology/CheckInDayDetail"
import { usePsychologyJournalInputs } from "@/lib/psychology/usePsychologyJournalInputs"
import { useUserProfile } from "@/lib/useUserProfile"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"

export default function CheckInDayPage() {
  useScrollPageTopOnMount()
  const params = useParams()
  const dateKey = String(params.dateKey ?? "")
  const { user } = useUserProfile()
  const { checkIns, trades, ready, setCheckIns, refresh } = usePsychologyJournalInputs(
    user?.id,
    []
  )

  return (
    <main className="tt-psych-experience mx-auto max-w-2xl px-4 py-8 md:py-10">
      <div className="mb-6">
        <Link
          href="/check-in-history"
          className="text-sm text-blue-400 hover:text-blue-300"
        >
          ← Check-In History
        </Link>
      </div>
      {!ready || !user?.id ? (
        <p className="text-sm text-gray-400">Loading…</p>
      ) : (
        <CheckInDayDetail
          userId={user.id}
          dateKey={dateKey}
          checkIns={checkIns}
          trades={trades}
          onCheckInSaved={(saved) => {
            setCheckIns((prev) => {
              const rest = prev.filter((row) => row.checkInDate !== saved.checkInDate)
              return [...rest, saved].sort((a, b) =>
                b.checkInDate.localeCompare(a.checkInDate)
              )
            })
            void refresh()
          }}
        />
      )}
    </main>
  )
}
