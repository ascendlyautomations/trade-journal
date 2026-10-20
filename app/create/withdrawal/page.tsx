"use client"

import { useRouter } from "next/navigation"
import CreatePageLayout from "@/app/components/create/CreatePageLayout"
import CreateWithdrawalFlow from "@/app/components/create/CreateWithdrawalFlow"
import { useCreatePagePrimaryAction } from "@/app/components/create/useCreatePagePrimaryAction"
import { useUserProfile } from "@/lib/UserProfileProvider"

export default function CreateWithdrawalPage() {
  const router = useRouter()
  const { user, loading } = useUserProfile()
  const { registerPrimary, invokePrimary, primaryDisabled, primaryBusy } =
    useCreatePagePrimaryAction()

  if (!loading && !user) {
    router.replace("/login")
    return null
  }

  return (
    <CreatePageLayout
      title="Withdrawal"
      subtitle="Record money taken out of a Live account or a funded prop-firm payout."
      backHref="/app"
      primaryLabel="Save Withdrawal"
      primaryBusy={primaryBusy}
      primaryDisabled={primaryDisabled}
      onPrimary={invokePrimary}
    >
      {user?.id ? (
        <CreateWithdrawalFlow userId={user.id} registerPrimary={registerPrimary} />
      ) : (
        <p className="text-sm text-gray-400">Loading…</p>
      )}
    </CreatePageLayout>
  )
}
