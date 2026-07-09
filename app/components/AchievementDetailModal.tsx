"use client"

import { useState } from "react"
import DetailModalShell from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import FeedAchievementDetailMeta from "@/app/components/feed/FeedAchievementDetailMeta"
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
          ) : (
            <div className="flex h-full w-full items-center justify-center p-6 text-sm text-white/45">
              No certificate image
            </div>
          )
        }
        splitPanel={
          <FeedAchievementDetailMeta achievement={achievement} showPrivacy />
        }
      />
      {lightboxUrl ? (
        <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
      ) : null}
    </>
  )
}
