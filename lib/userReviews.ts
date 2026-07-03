import { supabase } from "@/lib/supabaseClient"
import { notifyAdminSubmission } from "@/lib/notifyAdminSubmission"
import { isRateLimitExceededError, formatRateLimitExceededMessage } from "@/lib/rateLimitErrors"
import type { PostgrestError } from "@supabase/supabase-js"
import type { PublicUserReview } from "@/lib/userReviewDisplay"

export type { PublicUserReview } from "@/lib/userReviewDisplay"
export {
  computeUserReviewStats,
  formatUserReviewDisplayName,
  formatUserReviewUsername,
  resolvePublicReviewAvatar,
  selectFeaturedHomepageReviews,
} from "@/lib/userReviewDisplay"
export { SAMPLE_USER_REVIEWS } from "@/lib/demo/sampleUserReviews"
export { canSubmitUserReview } from "@/lib/userReviewAccess"

export type UserReviewStatus = "pending" | "approved" | "rejected"

export type UserReviewRow = {
  id: string
  user_id: string
  rating: number
  title: string | null
  review: string
  would_recommend: boolean
  status: UserReviewStatus
  featured: boolean
  display_name: string | null
  username_snapshot: string | null
  avatar_snapshot: string | null
  version: number
  created_at: string
  updated_at: string
}

export type UserReviewInput = {
  rating: number
  title: string
  review: string
  would_recommend: boolean
}

export type UserReviewProfileSnapshot = {
  name?: string | null
  username?: string | null
  avatar_url?: string | null
}

const USER_REVIEW_SELECT =
  "id, user_id, rating, title, review, would_recommend, status, featured, display_name, username_snapshot, avatar_snapshot, version, created_at, updated_at" as const

const REVIEW_MIN_LENGTH = 50
const REVIEW_MAX_LENGTH = 400

function logUserReviewError(context: string, error: PostgrestError): void {
  console.error(`[user-reviews] ${context}`, {
    code: error.code,
    message: error.message,
    details: error.details,
    hint: error.hint,
  })
}

export type FetchMyUserReviewResult = {
  data: UserReviewRow | null
  error: PostgrestError | null
}

export function normalizeUserReviewInput(input: UserReviewInput) {
  return {
    rating: Math.min(5, Math.max(1, Math.round(input.rating))),
    title: input.title.trim() || null,
    review: input.review.trim(),
    would_recommend: input.would_recommend,
  }
}

export function validateUserReviewInput(input: ReturnType<typeof normalizeUserReviewInput>): string | null {
  if (!Number.isFinite(input.rating) || input.rating < 1 || input.rating > 5) {
    return "Select a rating from 1 to 5 stars."
  }
  if (!input.review) {
    return "Review is required."
  }
  if (input.review.length < REVIEW_MIN_LENGTH) {
    return `Review should be at least ${REVIEW_MIN_LENGTH} characters.`
  }
  if (input.review.length > REVIEW_MAX_LENGTH) {
    return `Review should be ${REVIEW_MAX_LENGTH} characters or fewer.`
  }
  return null
}

function buildSnapshots(profile: UserReviewProfileSnapshot) {
  const displayName = profile.name?.trim() || null
  const username = profile.username?.trim() || null
  const avatar = profile.avatar_url?.trim() || null
  return {
    display_name: displayName,
    username_snapshot: username,
    avatar_snapshot: avatar,
  }
}

export async function fetchMyUserReview(userId: string): Promise<FetchMyUserReviewResult> {
  const { data, error } = await supabase
    .from("user_reviews")
    .select(USER_REVIEW_SELECT)
    .eq("user_id", userId)
    .maybeSingle()

  if (error) {
    logUserReviewError("fetch own failed", error)
    return { data: null, error }
  }

  return { data: (data as UserReviewRow | null) ?? null, error: null }
}

export async function fetchPublicUserReviews(): Promise<PublicUserReview[]> {
  const { data, error } = await supabase.rpc("list_public_user_reviews")

  if (error) {
    logUserReviewError("public fetch failed", error)
    return []
  }

  return (data as PublicUserReview[]) ?? []
}

export async function saveUserReview(
  userId: string,
  input: UserReviewInput,
  profile: UserReviewProfileSnapshot,
  existing: UserReviewRow | null
): Promise<{ ok: true; row: UserReviewRow } | { ok: false; message: string }> {
  const normalized = normalizeUserReviewInput(input)
  const validationError = validateUserReviewInput(normalized)
  if (validationError) {
    return { ok: false, message: validationError }
  }

  const snapshots = buildSnapshots(profile)
  const payload = {
    ...normalized,
    ...snapshots,
  }

  if (existing) {
    const { data, error } = await supabase
      .from("user_reviews")
      .update(payload)
      .eq("id", existing.id)
      .eq("user_id", userId)
      .select(USER_REVIEW_SELECT)
      .single()

    if (error) {
      return { ok: false, message: error.message }
    }

    notifyAdminSubmission("user_review", (data as UserReviewRow).id)
    return { ok: true, row: data as UserReviewRow }
  }

  const { data, error } = await supabase
    .from("user_reviews")
    .insert({
      user_id: userId,
      ...payload,
    })
    .select(USER_REVIEW_SELECT)
    .single()

  if (error) {
    if (error.code === "23505") {
      return {
        ok: false,
        message: "You already submitted a review. Edit your existing review instead.",
      }
    }
    if (isRateLimitExceededError(error.message)) {
      return {
        ok: false,
        message: formatRateLimitExceededMessage(
          "Too many review submissions today. Try again tomorrow."
        ),
      }
    }
    return { ok: false, message: error.message }
  }

  notifyAdminSubmission("user_review", (data as UserReviewRow).id)
  return { ok: true, row: data as UserReviewRow }
}
