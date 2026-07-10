import type { FeedbackPopupInput } from "../app/components/ui/feedback-popup-types.ts"
import { isPayoutAchievementType } from "./achievementTypes.ts"

export type AchievementFormField =
  | "achievement_type"
  | "title"
  | "payout_amount"
  | "achieved_at"
  | "image"
  | "account_name"

export type AchievementFormValidationInput = {
  achievement_type: string
  title: string
  payout_amount: string
  achieved_at: string
  hasImage: boolean
  accountId?: string | null
  requiresTradingAccount?: boolean
}

export type AchievementValidationResult =
  | { ok: true }
  | {
      ok: false
      kind: "missing"
      fields: AchievementFormField[]
    }
  | {
      ok: false
      kind: "invalid"
      field: AchievementFormField
      title: string
      message: string
    }

const FORM_FIELD_ORDER: AchievementFormField[] = [
  "achievement_type",
  "title",
  "payout_amount",
  "account_name",
  "achieved_at",
  "image",
]

const FIELD_LABELS: Record<AchievementFormField, string> = {
  achievement_type: "Achievement Type",
  title: "Achievement Title",
  payout_amount: "Payout Amount",
  account_name: "Trading Account",
  achieved_at: "Achievement Date",
  image: "Achievement Image",
}

const SINGLE_FIELD_POPUP: Record<
  AchievementFormField,
  { title: string; message: string }
> = {
  achievement_type: {
    title: "Achievement Type Required",
    message: "Please select an achievement type.",
  },
  title: {
    title: "Title Required",
    message: "Please enter an achievement title.",
  },
  payout_amount: {
    title: "Payout Required",
    message: "Please enter the payout amount.",
  },
  account_name: {
    title: "Trading Account Required",
    message:
      "Please select the trading account associated with this achievement.",
  },
  achieved_at: {
    title: "Date Required",
    message: "Please choose the achievement date.",
  },
  image: {
    title: "Image Required",
    message: "Please upload an achievement image.",
  },
}

function sortMissingFields(fields: AchievementFormField[]): AchievementFormField[] {
  const set = new Set(fields)
  return FORM_FIELD_ORDER.filter((field) => set.has(field))
}

export function collectAchievementFormMissingFields(
  input: AchievementFormValidationInput
): AchievementFormField[] {
  const missing: AchievementFormField[] = []
  const requiresPayout = isPayoutAchievementType(input.achievement_type)

  if (!String(input.achievement_type ?? "").trim()) {
    missing.push("achievement_type")
  }
  if (!String(input.title ?? "").trim()) {
    missing.push("title")
  }
  if (requiresPayout && !String(input.payout_amount ?? "").trim()) {
    missing.push("payout_amount")
  }
  if (input.requiresTradingAccount && !String(input.accountId ?? "").trim()) {
    missing.push("account_name")
  }
  if (!String(input.achieved_at ?? "").trim()) {
    missing.push("achieved_at")
  }
  if (!input.hasImage) {
    missing.push("image")
  }

  return sortMissingFields(missing)
}

/** Validates achievement form before submit — returns all missing fields at once. */
export function validateAchievementForm(
  input: AchievementFormValidationInput
): AchievementValidationResult {
  const missing = collectAchievementFormMissingFields(input)
  if (missing.length > 0) {
    return { ok: false, kind: "missing", fields: missing }
  }

  if (isPayoutAchievementType(input.achievement_type)) {
    const payoutAmount = Number(String(input.payout_amount).replace(/,/g, ""))
    if (!Number.isFinite(payoutAmount) || payoutAmount <= 0) {
      return {
        ok: false,
        kind: "invalid",
        field: "payout_amount",
        title: "Invalid Payout",
        message: "Please enter a valid payout amount.",
      }
    }
  }

  return { ok: true }
}

export function buildAchievementValidationPopup(
  result: Extract<AchievementValidationResult, { ok: false }>
): FeedbackPopupInput {
  if (result.kind === "invalid") {
    return {
      type: "error",
      title: result.title,
      message: result.message,
      persist: true,
    }
  }

  if (result.fields.length === 1) {
    const preset = SINGLE_FIELD_POPUP[result.fields[0]]
    return {
      type: "error",
      title: preset.title,
      message: preset.message,
      persist: true,
    }
  }

  const bullets = result.fields
    .map((field) => `• ${FIELD_LABELS[field]}`)
    .join("\n")

  return {
    type: "error",
    title: "Complete Required Fields",
    message: `Please complete:\n\n${bullets}\n\nbefore posting your achievement.`,
    persist: true,
  }
}
