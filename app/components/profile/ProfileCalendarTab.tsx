"use client"

import Calendar from "@/app/components/Calendar"
import ProfilePrivateTabMessage from "./ProfilePrivateTabMessage"
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
        <ProfilePrivateTabMessage />
      ) : loading ? (
        <div className="h-[420px] animate-pulse rounded-xl border border-white/10 bg-white/5" />
      ) : (
        <Calendar
          trades={trades as ComponentProps<typeof Calendar>["trades"]}
          showAccountFilter={false}
          showControls={false}
          showAccountIdentifiers={isOwnProfile}
          dayTradePresentation="profile"
        />
      )}
    </div>
  )
}

export default memo(ProfileCalendarTab)
