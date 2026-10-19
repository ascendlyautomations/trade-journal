"use client"

import { useCallback } from "react"
import { useRouter } from "next/navigation"
import CreatePageLayout from "@/app/components/create/CreatePageLayout"
import ReelComposerModal from "@/app/components/profile/ReelComposerModal"
import { useCreatePagePrimaryAction } from "@/app/components/create/useCreatePagePrimaryAction"
import { profilePath } from "@/lib/profileRoutes"
import { useUserProfile } from "@/lib/UserProfileProvider"

export default function CreateClipPage() {
  const router = useRouter()
  const { user, profile, loading } = useUserProfile()
  const { registerPrimary, invokePrimary, primaryDisabled, primaryBusy } =
    useCreatePagePrimaryAction()

  const handlePublished = useCallback(() => {
    if (profile) {
      router.push(`${profilePath(profile)}?tab=reels`)
      return
    }
    router.push("/feed")
  }, [profile, router])

  if (!loading && !user) {
    router.replace("/login")
    return null
  }

  return (
    <CreatePageLayout
      title="Create Clip"
      subtitle="Share a short vertical trading video with your followers."
      backHref="/feed"
      primaryLabel="Publish"
      primaryBusy={primaryBusy}
      primaryDisabled={primaryDisabled}
      onPrimary={invokePrimary}
    >
      <ReelComposerModal
        open
        layout="page"
        userId={user?.id ?? null}
        onClose={() => router.back()}
        onPublished={handlePublished}
        registerPrimary={registerPrimary}
      />
    </CreatePageLayout>
  )
}
