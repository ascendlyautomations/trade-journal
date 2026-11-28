"use client"

import type { Achievement } from "@/lib/achievements"
import {
  achievementTypeLabel,
  formatAchievementValue,
  isPayoutAchievementType,
} from "@/lib/achievements"
import { ACHIEVEMENT_TYPE, canonicalAchievementType } from "@/lib/achievementTypes"

function trimPublicFirm(firm: string | null | undefined): string | null {
  const trimmed = firm?.trim() ?? ""
  if (!trimmed) return null
  if (UUID_PATTERN.test(trimmed)) return null
  if (/^[0-9]{4,}$/.test(trimmed)) return null
  if (trimmed.toLowerCase() === "account") return null
  return trimmed
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function categoryContextLine(achievement: Achievement): string {
  const category = achievementTypeLabel(achievement.achievement_type)
  const canonical = canonicalAchievementType(achievement.achievement_type)
  const showsFirm =
    canonical === ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT ||
    canonical === ACHIEVEMENT_TYPE.PASSED_EVAL
  const firm = showsFirm ? trimPublicFirm(achievement.firm) : null
  return firm ? `${category} - ${firm}` : category
}

function primaryAmountDisplay(achievement: Achievement): string | null {
  return formatAchievementValue(achievement)
}

function amountToneClass(achievement: Achievement): string {
  if (
    isPayoutAchievementType(achievement.achievement_type) &&
    achievement.value_numeric != null &&
    Number.isFinite(Number(achievement.value_numeric))
  ) {
    const n = Number(achievement.value_numeric)
    return n > 0 ? "text-emerald-300" : "text-red-300"
  }
  return "text-white"
}

type AchievementPublicContentStackProps = {
  achievement: Achievement
  titleClassName?: string
  descriptionClassName?: string
}

/** Shared achievement copy stack (feed + detail + cards). */
export default function AchievementPublicContentStack({
  achievement,
  titleClassName = "text-sm font-semibold leading-snug text-white",
  descriptionClassName = "whitespace-pre-wrap text-sm leading-relaxed text-gray-300",
}: AchievementPublicContentStackProps) {
  const category = categoryContextLine(achievement)
  const amount = primaryAmountDisplay(achievement)
  const description =
    achievement.description != null && achievement.description.trim() !== ""
      ? achievement.description.trim()
      : null

  return (
    <div className="flex min-w-0 flex-col gap-1">
      <div className="flex min-w-0 items-baseline gap-2">
        <p className="min-w-0 flex-1 text-xs font-semibold leading-snug text-blue-300">
          {category}
        </p>
        {amount ? (
          <p
            className={`shrink-0 text-sm font-semibold tabular-nums ${amountToneClass(achievement)}`}
          >
            {amount}
          </p>
        ) : null}
      </div>
      <h3 className={`min-w-0 ${titleClassName}`}>{achievement.title}</h3>
      {description ? (
        <p className={`min-w-0 ${descriptionClassName}`}>{description}</p>
      ) : null}
    </div>
  )
}