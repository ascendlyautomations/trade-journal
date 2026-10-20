"use client"

import "../../utilityDesktopTheme.css"
import { useParams, useRouter } from "next/navigation"
import WithdrawalDetailClient from "@/app/components/withdrawals/WithdrawalDetailClient"
import { useUserProfile } from "@/lib/useUserProfile"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"

export default function WithdrawalDetailPage() {
  useScrollPageTopOnMount()
  const router = useRouter()
  const params = useParams()
  const { user, loading } = useUserProfile()
  const raw = params.itemId
  const historyItemId = decodeURIComponent(
    Array.isArray(raw) ? String(raw[0] ?? "") : String(raw ?? "")
  )

  if (!loading && !user) {
    router.replace("/login")
    return null
  }

  return (
    <div className="tt-phase4-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
      <div className="mx-auto max-w-2xl px-4 py-8 sm:px-6 lg:py-10">
        <WithdrawalDetailClient historyItemId={historyItemId} />
      </div>
    </div>
  )
}
