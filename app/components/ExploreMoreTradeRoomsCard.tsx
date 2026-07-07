"use client"

type ExploreMoreTradeRoomsCardProps = {
  onClick: () => void
  selected?: boolean
  className?: string
}

export default function ExploreMoreTradeRoomsCard({
  onClick,
  selected = false,
  className = "",
}: ExploreMoreTradeRoomsCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={selected ? "page" : undefined}
      className={
        `mt-1 flex min-h-[44px] w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left text-sm transition ` +
        (selected
          ? "border-white/25 bg-white/10 font-semibold text-white"
          : "border-dashed border-white/15 bg-white/[0.03] hover:border-white/25 hover:bg-white/[0.06]") +
        ` ${className}`
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
