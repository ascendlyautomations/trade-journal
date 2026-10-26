"use client"

import { useCallback, useState } from "react"
import DetailModalShell from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import EngagementShareButton from "@/app/components/EngagementShareButton"
import FeedAchievementDetailMeta from "@/app/components/feed/FeedAchievementDetailMeta"
import VaultEngagementButton from "@/app/components/vault/VaultEngagementButton"
import { DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS } from "@/app/components/ui/detailModalEngagement"
import type { Achievement } from "@/lib/achievements"
import { achievementImagePublicUrl } from "@/lib/storagePublicUrl"

type AchievementsPageDetailModalProps = {
  achievement: Achievement
  onClose: () => void
  onEdit: () => void
  onDelete: () => void
}

/** Personal achievement detail — /achievements page only (edit + delete). */
export default function AchievementsPageDetailModal({
  achievement,
  onClose,
  onEdit,
  onDelete,
}: AchievementsPageDetailModalProps) {
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)
  const imageSrc = achievementImagePublicUrl(achievement.image_url)

  const handleShare = useCallback(async () => {
    const text = `${achievement.title} on TradeTraxs`
    try {
      if (typeof navigator !== "undefined" && navigator.share) {
        await navigator.share({ title: achievement.title, text })
        return
      }
    } catch {
      /* user cancelled or share failed */
    }
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      /* ignore */
    }
  }, [achievement.title])

  const mediaActions = (
    <div className="flex w-full items-center gap-3 text-sm">
      <EngagementShareButton ariaLabel="Share achievement" onClick={() => void handleShare()} />
      <VaultEngagementButton
        contentRef={{
          contentType: "achievement",
          contentID: String(achievement.id),
        }}
        variant="boxed"
      />
    </div>
  )

  return (
    <>
      <DetailModalShell
        ariaLabel="Achievement details"
        title="Achievement"
        layout="split"
        backdropClassName="bg-black/75 backdrop-blur-md"
        onClose={onClose}
        splitMedia={
          imageSrc ? (
            <DetailModalImage src={imageSrc} onClick={setLightboxUrl} />
          ) : (
            <div className="flex h-full min-h-[8rem] w-full items-center justify-center p-4 text-sm text-gray-400">
              No certificate image
            </div>
          )
        }
        splitMediaActions={mediaActions}
        splitPanel={
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain md:hidden">
              <div className={DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS}>{mediaActions}</div>
            </div>
            <FeedAchievementDetailMeta achievement={achievement} showPrivacy />
            <div className="shrink-0 border-t border-white/10 px-4 py-2">
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={onEdit}
                  className="rounded-lg border border-white/20 bg-white/5 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/10"
                >
                  Edit
                </button>
                <button
                  type="button"
                  onClick={onDelete}
                  className="rounded-lg border border-red-400/40 bg-red-500/10 px-4 py-2 text-sm font-medium text-red-300 transition hover:bg-red-500/20"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        }
        suppressMobileSplitMedia
      />
      {lightboxUrl ? (
        <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
      ) : null}
    </>
  )
}
