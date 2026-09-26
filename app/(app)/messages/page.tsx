import type { Metadata } from "next"
import { MESSAGES_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = MESSAGES_PAGE_METADATA

export default function MessagesPage() {
  return (
    <div className="flex h-full min-h-0 flex-1 items-center justify-center px-6 text-sm text-gray-300">
      <div className="rounded-xl border border-white/10 bg-white/5 px-8 py-6 backdrop-blur-md">
        Select a conversation
      </div>
    </div>
  )
}
