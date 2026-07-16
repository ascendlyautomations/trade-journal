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
      className={`text-xs font-medium text-gray-400 transition-colors hover:text-gray-300 ${className}`}
    >
      {label}
    </button>
  )
}
