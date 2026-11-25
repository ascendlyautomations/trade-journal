"use client"

import { MESSAGE_REACTIONS } from "@/lib/roomMessageReactions"

type Props = {
  onQuickPick: (emoji: string) => void
  onOpenFullPicker: () => void
  buttonClassName?: string
  plusClassName?: string
  emojiClassName?: string
}

export default function MessageReactionQuickRow({
  onQuickPick,
  onOpenFullPicker,
  buttonClassName = "flex h-10 w-10 items-center justify-center rounded-full text-lg active:bg-white/10 hover:bg-white/10",
  plusClassName = "text-sm font-semibold text-gray-300",
  emojiClassName,
}: Props) {
  return (
    <div className="flex items-center justify-center gap-1" role="group" aria-label="React to message">
      {MESSAGE_REACTIONS.map((emoji) => (
        <button
          key={emoji}
          type="button"
          className={emojiClassName ?? buttonClassName}
          aria-label={`React with ${emoji}`}
          onClick={() => onQuickPick(emoji)}
        >
          {emoji}
        </button>
      ))}
      <button
        type="button"
        className={buttonClassName}
        aria-label="More emoji reactions"
        onClick={onOpenFullPicker}
      >
        <span className={plusClassName} aria-hidden>
          +
        </span>
      </button>
    </div>
  )
}