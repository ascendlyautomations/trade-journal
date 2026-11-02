"use client"

import { ChevronLeft } from "lucide-react"

type MobileWebSettingsSectionHeaderProps = {
  title: string
  onBack: () => void
}

export default function MobileWebSettingsSectionHeader({
  title,
  onBack,
}: MobileWebSettingsSectionHeaderProps) {
  return (
    <div className="mb-3 flex h-11 items-center gap-1">
      <button
        type="button"
        onClick={onBack}
        aria-label="Back"
        className="inline-flex h-11 min-w-11 items-center justify-center gap-0.5 rounded-full text-[#4EC4E0]"
      >
        <ChevronLeft className="h-6 w-6" strokeWidth={2} aria-hidden />
        <span className="sr-only">Back</span>
      </button>
      <h2 className="min-w-0 flex-1 truncate text-center text-[17px] font-semibold tracking-tight text-[color:var(--tt-text,#1f2328)]">
        {title}
      </h2>
      <span className="inline-block h-11 w-11 shrink-0" aria-hidden />
    </div>
  )
}
