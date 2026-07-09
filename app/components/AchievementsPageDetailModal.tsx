"use client"

import { useState } from "react"
import DetailModalShell from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import {
  type Achievement,
  achievementTypeLabel,
  badgeIconForKey,
  formatAchievementDate,
  formatAchievementValue,
  isPayoutAchievementType,
} from "@/lib/achievements"
import { achievementImagePublicUrl } from "@/lib/storagePublicUrl"

type AchievementsPageDetailModalProps = {
  achievement: Achievement
  onClose: () => void
  onEdit: () => void
  onDelete: () => void
}

function formatValueHeadline(achievement: Achievement): string | null {
  const valueText = formatAchievementValue(achievement)
  if (!valueText) return null

  if (isPayoutAchievementType(achievement.achievement_type)) {
    return `${valueText} ${achievementTypeLabel(achievement.achievement_type)}`
  }

  return valueText
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
  const valueHeadline = formatValueHeadline(achievement)
  const typeLabel = achievementTypeLabel(achievement.achievement_type)
  const description =
    achievement.description != null && achievement.description.trim() !== ""
      ? achievement.description.trim()
      : null

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
            <div className="flex h-full w-full items-center justify-center p-6 text-sm text-white/45">
              No certificate image
            </div>
          )
        }
        splitPanel={
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1 space-y-2">
                  <p className="text-xs uppercase tracking-wide text-blue-200/80">
                    {typeLabel}
                  </p>
                  <h3 className="text-lg font-semibold leading-snug text-white">
                    {achievement.title}
                  </h3>
                  {valueHeadline ? (
                    <p className="text-base font-semibold text-emerald-300">
                      {valueHeadline}
                    </p>
                  ) : null}
                  {description ? (
                    <p className="whitespace-pre-wrap text-sm leading-relaxed text-gray-300">
                      {description}
                    </p>
                  ) : null}
                  <div className="space-y-0.5 pt-1 text-xs text-gray-400">
                    <p>{formatAchievementDate(achievement.achieved_at)}</p>
                    <p>{achievement.is_public ? "Public" : "Private"}</p>
                  </div>
                </div>
                <span className="shrink-0 text-2xl leading-none">
                  {badgeIconForKey(achievement.badge_key, achievement.achievement_type)}
                </span>
              </div>
            </div>

            <div className="shrink-0 border-t border-white/10 px-4 py-3">
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
      />
      {lightboxUrl ? (
        <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
      ) : null}
    </>
  )
}
