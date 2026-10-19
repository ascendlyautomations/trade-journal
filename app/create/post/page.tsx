"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import CreatePageLayout from "@/app/components/create/CreatePageLayout"
import CreatePostComposer, {
  resolvePendingRoomShareFromQuery,
} from "@/app/components/create/CreatePostComposer"
import CreatePostFeedPreview, {
  type CreatePostDraftSnapshot,
} from "@/app/components/create/CreatePostFeedPreview"
import { useCreatePagePrimaryAction } from "@/app/components/create/useCreatePagePrimaryAction"
import { profilePath } from "@/lib/profileRoutes"
import type { PendingRoomShareDraft } from "@/lib/roomSharePost"
import { useUserProfile } from "@/lib/UserProfileProvider"

const EMPTY_DRAFT: CreatePostDraftSnapshot = {
  content: "",
  imagePreviewUrl: null,
  pendingRoomShare: null,
}

export default function CreatePostPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { user, profile, loading } = useUserProfile()
  const [roomShare, setRoomShare] = useState<PendingRoomShareDraft | null>(null)
  const [draft, setDraft] = useState<CreatePostDraftSnapshot>(EMPTY_DRAFT)
  const { registerPrimary, invokePrimary, primaryDisabled, primaryBusy } =
    useCreatePagePrimaryAction()

  useEffect(() => {
    const roomId = searchParams.get("shareRoom")?.trim() ?? ""
    if (!roomId) return
    void resolvePendingRoomShareFromQuery(roomId).then(setRoomShare)
  }, [searchParams])

  const handleDraftChange = useCallback((snapshot: CreatePostDraftSnapshot) => {
    setDraft(snapshot)
  }, [])

  const handlePublished = useCallback(() => {
    if (profile) {
      router.push(`${profilePath(profile)}?tab=posts`)
      return
    }
    router.push("/feed")
  }, [profile, router])

  if (!loading && !user) {
    router.replace("/login")
    return null
  }

  const previewUser = user?.id ? { id: user.id } : null

  return (
    <CreatePageLayout
      title="Create Post"
      subtitle="Share trades and updates with the community."
      backHref="/feed"
      primaryLabel="Publish"
      primaryBusy={primaryBusy}
      primaryDisabled={primaryDisabled}
      onPrimary={invokePrimary}
      preview={
        <CreatePostFeedPreview
          draft={draft}
          userId={user?.id ?? null}
          username={profile?.username ?? null}
          avatarUrl={profile?.avatar_url ?? null}
          user={previewUser}
        />
      }
    >
      <CreatePostComposer
        layout="page"
        initialRoomShare={roomShare}
        onPublished={handlePublished}
        registerPrimary={registerPrimary}
        onDraftChange={handleDraftChange}
      />
    </CreatePageLayout>
  )
}
