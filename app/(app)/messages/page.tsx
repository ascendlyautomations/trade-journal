import type { Metadata } from "next"
import { MESSAGES_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = MESSAGES_PAGE_METADATA

export default function MessagesPage() {
  return (
    <div className="flex h-full min-h-0 flex-1 items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 text-sm text-gray-300">
      <div className="rounded-xl border border-white/10 bg-black/30 px-8 py-6">
        Select a conversation
      </div>
    </div>
  )
}
