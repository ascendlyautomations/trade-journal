"use client"

import { useCallback } from "react"
import { useRouter } from "next/navigation"
import CreatePageLayout from "@/app/components/create/CreatePageLayout"
import AchievementUploadModal from "@/app/components/AchievementUploadModal"
import { useCreatePagePrimaryAction } from "@/app/components/create/useCreatePagePrimaryAction"
import { useUserProfile } from "@/lib/UserProfileProvider"

export default function CreateAchievementPage() {
  const router = useRouter()
  const { user, loading } = useUserProfile()
  const { registerPrimary, invokePrimary, primaryBusy } =
    useCreatePagePrimaryAction()

  const handleSaved = useCallback(() => {
    router.push("/achievements")
  }, [router])

  if (!loading && !user) {
    router.replace("/login")
    return null
  }

  return (
    <CreatePageLayout
      title="Create Achievement"
      subtitle="Capture payouts, passed evals, and trading milestones."
      backHref="/achievements"
      primaryLabel="Save Achievement"
      primaryBusy={primaryBusy}
      onPrimary={invokePrimary}
    >
      <AchievementUploadModal
        open
        layout="page"
        userId={user?.id ?? null}
        onClose={() => router.back()}
        onSaved={handleSaved}
        registerPrimary={registerPrimary}
      />
    </CreatePageLayout>
  )
}
