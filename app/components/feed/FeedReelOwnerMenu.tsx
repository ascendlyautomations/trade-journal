"use client"

import { memo } from "react"

type FeedReelOwnerMenuProps = {
  menuOpen: boolean
  onMenuToggle: () => void
  onEdit: () => void
  onDelete: () => void
  onReplaceVideo?: () => void
  isTradeAttached?: boolean
}

/** Owner ••• menu for reels — matches profile PostCard ordering (Edit, Delete). */
function FeedReelOwnerMenu({
  menuOpen,
  onMenuToggle,
  onEdit,
  onDelete,
  onReplaceVideo,
  isTradeAttached = false,
}: FeedReelOwnerMenuProps) {
  return (
    <div className="relative shrink-0">
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          onMenuToggle()
        }}
        className="px-1 text-gray-400 hover:text-white"
        aria-label="Clip options"
      >
        •••
      </button>
      {menuOpen ? (
        <div
          className="absolute right-0 z-50 mt-2 w-44 rounded-lg border border-white/10 bg-[#020617] shadow-lg"
          onClick={(e) => e.stopPropagation()}
        >
          {isTradeAttached ? (
            <>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onReplaceVideo?.()
                }}
                className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
              >
                Replace Video
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onDelete()
                }}
                className="block w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-white/10"
              >
                Delete Replay
              </button>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onEdit()
                }}
                className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
              >
                Edit Clip
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onDelete()
                }}
                className="block w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-white/10"
              >
                Delete Clip
              </button>
            </>
          )}
        </div>
      ) : null}
    </div>
  )
}

export default memo(FeedReelOwnerMenu)
