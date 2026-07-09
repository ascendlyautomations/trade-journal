"use client"

import {
  type Achievement,
  achievementTypeLabel,
  badgeIconForKey,
  formatAchievementDate,
  formatAchievementValue,
  isPayoutAchievementType,
  tierClassName,
} from "../../lib/achievements"
import { achievementImagePublicUrl } from "../../lib/storagePublicUrl"
import { CONTENT_IMAGE_DISPLAY_PRESET } from "@/lib/contentImagePipeline"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"

type AchievementCardProps = {
  achievement: Achievement
  featured?: boolean
  showVisibility?: boolean
  onOpenDetail?: (achievement: Achievement) => void
  onEdit?: () => void
  onDelete?: () => void
  /** @deprecated Prefer onOpenDetail — opens the full achievement modal. */
  onImageClick?: (imageSrc: string, achievement: Achievement) => void
}

export default function AchievementCard({
  achievement,
  featured = false,
  showVisibility = true,
  onOpenDetail,
  onEdit,
  onDelete,
  onImageClick,
}: AchievementCardProps) {
  const imageSrc = achievementImagePublicUrl(achievement.image_url)
  const valueText = formatAchievementValue(achievement)
  const isPayout = isPayoutAchievementType(achievement.achievement_type)
  const headerLabel =
    isPayout && valueText
      ? `${achievementTypeLabel(achievement.achievement_type)} • ${valueText}`
      : achievementTypeLabel(achievement.achievement_type)

  const openDetail = onOpenDetail
    ? () => onOpenDetail(achievement)
    : onImageClick && imageSrc
      ? () => onImageClick(imageSrc, achievement)
      : undefined

  const imageNode = imageSrc ? (
    <TradeScreenshotImage
      src={imageSrc}
      preset={CONTENT_IMAGE_DISPLAY_PRESET}
      alt={achievement.title}
      className="rounded-md border border-white/10"
      logContext="achievement-card"
    />
  ) : null

  return (
    <article
      className={`rounded-xl border p-4 ${tierClassName(achievement.tier ?? null)} ${
        openDetail
          ? "cursor-pointer transition hover:border-white/20 hover:bg-white/[0.03]"
          : ""
      }`}
      role={openDetail ? "button" : undefined}
      tabIndex={openDetail ? 0 : undefined}
      onClick={openDetail ? () => openDetail() : undefined}
      onKeyDown={
        openDetail
          ? (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                openDetail()
              }
            }
          : undefined
      }
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-[11px] uppercase tracking-wide text-blue-200/80">
            {headerLabel}
          </p>
          <h3 className="truncate text-sm font-semibold text-white">{achievement.title}</h3>
          {featured ? (
            <p className="text-xs text-gray-300">{achievement.description || "Achievement unlocked"}</p>
          ) : null}
        </div>
        <span className="text-lg leading-none">
          {badgeIconForKey(achievement.badge_key, achievement.achievement_type)}
        </span>
      </div>

      {!featured ? (
        <p className="mt-1 text-xs text-gray-300">
          {achievement.description || "Achievement unlocked"}
        </p>
      ) : null}

      {(featured || valueText) && !(isPayout && valueText) ? (
        <p className="mt-1 text-xs text-emerald-300">{valueText || "Achievement unlocked"}</p>
      ) : null}

      <p className="mt-1 text-[11px] text-gray-400">
        {featured ? "Achieved " : ""}
        {formatAchievementDate(achievement.achieved_at)}
        {!featured && showVisibility ? ` • ${achievement.is_public ? "Public" : "Private"}` : ""}
      </p>

      {imageNode ? (
        onOpenDetail ? (
          <div className="mt-2">{imageNode}</div>
        ) : onImageClick ? (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onImageClick(imageSrc!, achievement)
            }}
            className="group mt-2 block w-full text-left transition group-hover:brightness-110"
            aria-label={`Open image for ${achievement.title}`}
          >
            {imageNode}
          </button>
        ) : (
          <div className="mt-2">{imageNode}</div>
        )
      ) : null}

      {onEdit || onDelete ? (
        <div
          className="mt-3 flex gap-2"
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
        >
          {onEdit ? (
            <button
              type="button"
              onClick={onEdit}
              className="rounded-md border border-white/20 px-2 py-1 text-xs hover:bg-white/10"
            >
              Edit
            </button>
          ) : null}
          {onDelete ? (
            <button
              type="button"
              onClick={onDelete}
              className="rounded-md border border-red-400/40 px-2 py-1 text-xs text-red-300 hover:bg-red-500/10"
            >
              Delete
            </button>
          ) : null}
        </div>
      ) : null}
    </article>
  )
}
