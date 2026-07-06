"use client"

type ExploreMoreTradeRoomsCardProps = {
  onClick: () => void
  className?: string
}

export default function ExploreMoreTradeRoomsCard({
  onClick,
  className = "",
}: ExploreMoreTradeRoomsCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        `mt-1 flex min-h-[44px] w-full items-center gap-3 rounded-lg border border-dashed border-white/15 bg-white/[0.03] px-3 py-2 text-left text-sm transition hover:border-white/25 hover:bg-white/[0.06] ` +
        className
      }
    >
      <div
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/10 text-base font-semibold leading-none text-gray-200"
        aria-hidden
      >
        +
      </div>
      <span className="min-w-0 flex-1 truncate font-medium text-gray-200">
        Explore More Trade Rooms
      </span>
    </button>
  )
}
