"use client"

import Calendar from "@/app/components/Calendar"
import { memo, type ComponentProps } from "react"
import type { ProfileTradeRow } from "./profileTypes"

type ProfileCalendarTabProps = {
  canView: boolean
  loading: boolean
  trades: ProfileTradeRow[]
  isOwnProfile: boolean
}

function ProfileCalendarTab({
  canView,
  loading,
  trades,
  isOwnProfile,
}: ProfileCalendarTabProps) {
  return (
    <div className="mt-4">
      {!canView ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
          <p className="text-lg text-gray-100">Private Profile</p>
          <p className="mt-2 text-sm text-gray-400">
            Follow this user to see their trades and stats.
          </p>
        </div>
      ) : loading ? (
        <div className="h-[420px] animate-pulse rounded-xl border border-white/10 bg-white/5" />
      ) : (
        <Calendar
          trades={trades as ComponentProps<typeof Calendar>["trades"]}
          showAccountFilter={false}
          showControls={false}
          showAccountIdentifiers={isOwnProfile}
        />
      )}
    </div>
  )
}

export default memo(ProfileCalendarTab)
