"use client"

import { useEffect, useState } from "react"
import {
  type Achievement,
  formatAchievementValue,
  isPayoutAchievementType,
} from "@/lib/achievements"
import { phoneWebThumbnailSrc } from "@/lib/mobileWebMedia"
import { achievementImagePublicUrl } from "@/lib/storagePublicUrl"
import { Trophy } from "lucide-react"

type MobileWebProfileAchievementGridProps = {
  achievements: Achievement[]
  onOpenDetail: (achievement: Achievement) => void
}

function achievementThumbSource(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("/") || raw.startsWith("http") || raw.startsWith("blob:")) return raw
  return achievementImagePublicUrl(raw)
}

function AchievementThumb({ src }: { src: string | null }) {
  const [failed, setFailed] = useState(false)
  const [current, setCurrent] = useState<string | null>(() =>
    src ? phoneWebThumbnailSrc(src, 384) : null
  )

  useEffect(() => {
    setFailed(false)
    setCurrent(src ? phoneWebThumbnailSrc(src, 384) : null)
  }, [src])

  if (!src || failed) {
    return (
      <span className="absolute inset-0 flex items-center justify-center">
        <Trophy
          className="h-8 w-8 text-[color:var(--tt-text-muted,#57606a)]"
          strokeWidth={1.75}
          aria-hidden
        />
      </span>
    )
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={current ?? src}
      alt=""
      loading="lazy"
      decoding="async"
      className="absolute inset-0 h-full w-full object-cover"
      onError={() => {
        if (current !== src) {
          setCurrent(src)
          return
        }
        setFailed(true)
      }}
    />
  )
}

function payoutTone(achievement: Achievement) {
  if (!isPayoutAchievementType(achievement.achievement_type)) return "text-white"
  const n = Number(achievement.value_numeric)
  if (!Number.isFinite(n) || n === 0) return "text-white"
  return n > 0 ? "text-emerald-300" : "text-red-300"
}

export default function MobileWebProfileAchievementGrid({
  achievements,
  onOpenDetail,
}: MobileWebProfileAchievementGridProps) {
  return (
    <div
      className="grid grid-cols-2 gap-0.5"
      data-testid="mobile-web-profile-achievements-grid"
    >
      {achievements.map((achievement) => {
        const imageSrc = achievementThumbSource(achievement.image_url)
        const valueText = formatAchievementValue(achievement)
        return (
          <button
            key={achievement.id}
            type="button"
            onClick={() => onOpenDetail(achievement)}
            className="relative aspect-square overflow-hidden rounded-[8px] bg-[color:var(--tt-surface-nested,#f3f4f6)] text-left"
            aria-label={achievement.title}
          >
            <AchievementThumb src={imageSrc} />
            <span className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/75 to-transparent px-2 pb-2 pt-6">
              <span className="line-clamp-2 text-[12px] font-semibold leading-tight text-white">
                {achievement.title}
              </span>
              {valueText ? (
                <span
                  className={`mt-0.5 block truncate text-[11px] font-semibold tabular-nums ${payoutTone(
                    achievement
                  )}`}
                >
                  {valueText}
                </span>
              ) : null}
            </span>
          </button>
        )
      })}
    </div>
  )
}
