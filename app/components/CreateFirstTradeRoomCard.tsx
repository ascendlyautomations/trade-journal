"use client"

type CreateFirstTradeRoomCardProps = {
  onClick: () => void
  disabled?: boolean
  selected?: boolean
  className?: string
}

export default function CreateFirstTradeRoomCard({
  onClick,
  disabled = false,
  selected = false,
  className = "",
}: CreateFirstTradeRoomCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-current={selected ? "page" : undefined}
      className={
        `mb-1 flex min-h-[44px] w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left text-sm transition disabled:cursor-not-allowed disabled:opacity-60 ` +
        (selected
          ? "border-blue-400/40 bg-blue-500/25 font-semibold text-blue-100"
          : "border-blue-400/30 bg-blue-500/10 hover:bg-blue-500/15") +
        ` ${className}`
      }
    >
      <div
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-500/20 text-base font-semibold leading-none text-blue-200"
        aria-hidden
      >
        +
      </div>
      <div className="min-w-0 flex-1">
        <span className="block truncate font-semibold text-blue-100">
          Create Your Own Trade Room
        </span>
        <span className="mt-0.5 line-clamp-2 text-xs font-normal leading-snug text-blue-200/75">
          Build your own community, chat with traders, share trades, and grow
          together.
        </span>
      </div>
    </button>
  )
}
