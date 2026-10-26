"use client"

import { useState } from "react"
import DetailModalShell from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import FeedAchievementDetailMeta from "@/app/components/feed/FeedAchievementDetailMeta"
import VaultEngagementButton from "@/app/components/vault/VaultEngagementButton"
import type { Achievement } from "@/lib/achievements"
import { achievementImagePublicUrl } from "@/lib/storagePublicUrl"

type AchievementDetailModalProps = {
  achievement: Achievement
  onClose: () => void
}

/** Read-only achievement detail — same split layout as feed achievement posts. */
export default function AchievementDetailModal({
  achievement,
  onClose,
}: AchievementDetailModalProps) {
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)
  const imageSrc = achievementImagePublicUrl(achievement.image_url)

  return (
    <>
      <DetailModalShell
        ariaLabel="Achievement details"
        layout="split"
        onClose={onClose}
        splitMedia={
          imageSrc ? (
            <DetailModalImage src={imageSrc} onClick={setLightboxUrl} />
          ) : undefined
        }
        splitMediaActions={
          imageSrc ? (
            <div className="flex w-full items-center gap-3">
              <VaultEngagementButton
                contentRef={{
                  contentType: "achievement",
                  contentID: String(achievement.id),
                }}
                variant="boxed"
              />
            </div>
          ) : undefined
        }
        splitPanel={
          <div className="flex min-h-0 flex-col">
            {!imageSrc ? (
              <div className="flex justify-end border-b border-white/10 px-4 py-1">
                <VaultEngagementButton
                  contentRef={{
                    contentType: "achievement",
                    contentID: String(achievement.id),
                  }}
                  variant="boxed"
                />
              </div>
            ) : null}
            <FeedAchievementDetailMeta achievement={achievement} showPrivacy />
          </div>
        }
      />
      {lightboxUrl ? (
        <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
      ) : null}
    </>
  )
}
