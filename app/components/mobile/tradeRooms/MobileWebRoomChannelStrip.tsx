"use client"

import type { ReactNode } from "react"

type Section = {
  id: string
  name?: string | null
}

type MobileWebRoomChannelStripProps = {
  sections: Section[]
  selectedSectionId: string | null
  onSelect: (sectionId: string) => void
  isOwner: boolean
  onAddChannel?: () => void
  canAddChannel: boolean
  generalVoiceSlot?: ReactNode
}

export default function MobileWebRoomChannelStrip({
  sections,
  selectedSectionId,
  onSelect,
  isOwner,
  onAddChannel,
  canAddChannel,
  generalVoiceSlot,
}: MobileWebRoomChannelStripProps) {
  if (sections.length === 0 && !generalVoiceSlot) return null

  return (
    <div
      className="shrink-0 border-b border-white/10"
      data-tt-mobile-room-channel-strip
    >
      {generalVoiceSlot ? (
        <div className="border-b border-white/10 px-3 py-2">{generalVoiceSlot}</div>
      ) : null}
      {sections.length > 0 ? (
        <div className="tt-mobile-web-hscroll flex gap-2 overflow-x-auto px-3 py-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {sections.map((section) => {
            const selected = section.id === selectedSectionId
            return (
              <button
                key={section.id}
                type="button"
                onClick={() => onSelect(section.id)}
                aria-current={selected ? "true" : undefined}
                className={`shrink-0 rounded-full px-3 py-1.5 text-[13px] font-medium transition ${
                  selected
                    ? "bg-[#4EC4E0] text-[#0b1220]"
                    : "bg-white/10 text-[color:var(--tt-text,#f0f3f6)]"
                }`}
              >
                {section.name}
              </button>
            )
          })}
          {isOwner && canAddChannel && onAddChannel ? (
            <button
              type="button"
              onClick={onAddChannel}
              className="shrink-0 rounded-full border border-dashed border-white/25 px-3 py-1.5 text-[13px] font-medium text-emerald-400"
            >
              + Channel
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
