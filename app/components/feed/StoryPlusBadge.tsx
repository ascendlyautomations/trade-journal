"use client"

type StoryPlusBadgeProps = {
  onClick: () => void
}

export default function StoryPlusBadge({ onClick }: StoryPlusBadgeProps) {
  return (
    <button
      type="button"
      aria-label="Add story"
      onClick={(e) => {
        e.stopPropagation()
        onClick()
      }}
      className="tt-mobile-web-hit-slop absolute -bottom-0.5 -right-0.5 z-10 flex h-5 w-5 items-center justify-center rounded-full border-2 border-[color:var(--tt-surface,#0f172a)] bg-emerald-500 text-[13px] font-bold leading-none text-white shadow-md transition hover:bg-emerald-400 active:scale-95"
    >
      +
    </button>
  )
}