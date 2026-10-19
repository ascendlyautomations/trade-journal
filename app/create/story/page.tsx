"use client"

import { useCallback } from "react"
import { useRouter } from "next/navigation"
import CreatePageLayout from "@/app/components/create/CreatePageLayout"
import CreateStoryComposer from "@/app/components/create/CreateStoryComposer"
import { useCreatePagePrimaryAction } from "@/app/components/create/useCreatePagePrimaryAction"
import { useUserProfile } from "@/lib/UserProfileProvider"

export default function CreateStoryPage() {
  const router = useRouter()
  const { user, loading } = useUserProfile()
  const { registerPrimary, invokePrimary, primaryDisabled, primaryBusy } =
    useCreatePagePrimaryAction()

  const handlePosted = useCallback(() => {
    router.push("/feed")
  }, [router])

  if (!loading && !user) {
    router.replace("/login")
    return null
  }

  return (
    <CreatePageLayout
      title="Create Story"
      subtitle="Share a photo that stays visible for 24 hours."
      backHref="/feed"
      primaryLabel="Post Story"
      primaryBusy={primaryBusy}
      primaryDisabled={primaryDisabled}
      onPrimary={invokePrimary}
    >
      <CreateStoryComposer
        layout="page"
        onPosted={handlePosted}
        registerPrimary={registerPrimary}
      />
    </CreatePageLayout>
  )
}
