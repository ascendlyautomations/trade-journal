"use client"

type ReplyActionButtonProps = {
  onReply: () => void
  className?: string
  label?: string
}

export default function ReplyActionButton({
  onReply,
  className = "",
  label = "Reply",
}: ReplyActionButtonProps) {
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation()
        onReply()
      }}
      className={`rounded px-1.5 py-0.5 text-xs text-gray-400 opacity-0 transition-opacity hover:text-gray-200 group-hover:opacity-100 ${className}`}
    >
      {label}
    </button>
  )
}
