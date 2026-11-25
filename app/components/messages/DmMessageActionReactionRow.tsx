"use client"

import { useState } from "react"
import MessageReactionQuickRow from "@/app/components/messages/MessageReactionQuickRow.tsx"
import UnicodeEmojiPickerOverlay from "@/app/components/messages/UnicodeEmojiPickerOverlay.tsx"

type Props = {
  onSelectReaction: (emoji: string) => void
  onCloseMenu: () => void
}

export default function DmMessageActionReactionRow({
  onSelectReaction,
  onCloseMenu,
}: Props) {
  const [pickerOpen, setPickerOpen] = useState(false)

  const pick = (emoji: string) => {
    onSelectReaction(emoji)
    onCloseMenu()
    setPickerOpen(false)
  }

  return (
    <>
      <div className="border-b border-white/10 px-2 py-2">
        <MessageReactionQuickRow
          onQuickPick={pick}
          onOpenFullPicker={() => setPickerOpen(true)}
          buttonClassName="rounded-md px-1.5 py-1 text-base hover:bg-white/10 min-w-9 min-h-9"
          plusClassName="text-sm font-semibold text-gray-300"
        />
      </div>
      <UnicodeEmojiPickerOverlay
        open={pickerOpen}
        onClose={() => setPickerOpen(false)}
        onPick={pick}
      />
    </>
  )
}