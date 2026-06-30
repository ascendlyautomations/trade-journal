"use client"

import { memo } from "react"

type FeedReelOwnerMenuProps = {
  menuOpen: boolean
  onMenuToggle: () => void
  onEdit: () => void
  onDelete: () => void
}

/** Owner ••• menu for reels — matches profile PostCard ordering (Edit, Delete). */
function FeedReelOwnerMenu({
  menuOpen,
  onMenuToggle,
  onEdit,
  onDelete,
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
        aria-label="Reel options"
      >
        •••
      </button>
      {menuOpen ? (
        <div
          className="absolute right-0 z-50 mt-2 w-40 rounded-lg border border-white/10 bg-[#020617] shadow-lg"
          onClick={(e) => e.stopPropagation()}
        >
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onEdit()
            }}
            className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
          >
            Edit Reel
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onDelete()
            }}
            className="block w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-white/10"
          >
            Delete Reel
          </button>
        </div>
      ) : null}
    </div>
  )
}

export default memo(FeedReelOwnerMenu)
