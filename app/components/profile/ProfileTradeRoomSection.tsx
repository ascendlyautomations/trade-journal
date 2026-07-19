"use client"

import { Button } from "@/app/components/ui"

type ProfileTradeRoomSectionProps = {
  isOwnProfile: boolean
  hasRoom: boolean
  canShowVisitorRoomCta: boolean
  onCreateRoom: () => void
  onViewRoom: () => void
}

export default function ProfileTradeRoomSection({
  isOwnProfile,
  hasRoom,
  canShowVisitorRoomCta,
  onCreateRoom,
  onViewRoom,
}: ProfileTradeRoomSectionProps) {
  if (isOwnProfile) {
    if (hasRoom) {
      return (
        <div className="mt-3 flex flex-wrap items-center justify-center gap-2 sm:justify-start">
          <Button
            type="button"
            variant="primary"
            size="md"
            onClick={onViewRoom}
            className="px-4 py-1.5 sm:px-4 sm:py-1.5"
          >
            View Trade Room
          </Button>
        </div>
      )
    }

    return (
      <div className="mt-3 flex flex-wrap items-center justify-center gap-2 sm:justify-start">
        <button
          type="button"
          onClick={onCreateRoom}
          className="rounded-xl bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 sm:px-4 sm:py-1.5"
        >
          Create Trade Room
        </button>
      </div>
    )
  }

  if (!canShowVisitorRoomCta) return null

  return (
    <div className="mt-3">
      <Button
        type="button"
        variant="primary"
        size="md"
        onClick={onViewRoom}
        className="px-4 py-1.5 sm:px-4 sm:py-1.5"
      >
        View Trade Room
      </Button>
    </div>
  )
}
