import { supabase } from "@/lib/supabaseClient"
import type { PublicBetaTestimonial } from "@/lib/betaTestimonialDisplay"

export type { PublicBetaTestimonial } from "@/lib/betaTestimonialDisplay"
export {
  computeBetaTestimonialStats,
  formatTradingExperienceLabel,
  selectHomepageTestimonials,
} from "@/lib/betaTestimonialDisplay"

export type BetaTestimonialRow = {
  id: string
  user_id: string
  rating: number
  title: string
  review: string
  pros: string | null
  cons: string | null
  would_recommend: boolean
  approved: boolean
  featured: boolean
  created_at: string
  updated_at: string
}

export type BetaTestimonialInput = {
  rating: number
  title: string
  review: string
  pros: string
  cons: string
  would_recommend: boolean
}

const BETA_TESTIMONIAL_SELECT =
  "id, user_id, rating, title, review, pros, cons, would_recommend, approved, featured, created_at, updated_at" as const

export function normalizeBetaTestimonialInput(input: BetaTestimonialInput) {
  return {
    rating: Math.min(5, Math.max(1, Math.round(input.rating))),
    title: input.title.trim(),
    review: input.review.trim(),
    pros: input.pros.trim() || null,
    cons: input.cons.trim() || null,
    would_recommend: input.would_recommend,
  }
}

export async function fetchMyBetaTestimonial(
  userId: string
): Promise<BetaTestimonialRow | null> {
  const { data, error } = await supabase
    .from("beta_testimonials")
    .select(BETA_TESTIMONIAL_SELECT)
    .eq("user_id", userId)
    .maybeSingle()

  if (error) {
    console.error("[beta-testimonials] fetch own failed", error)
    return null
  }

  return (data as BetaTestimonialRow | null) ?? null
}

export async function fetchPublicBetaTestimonials(): Promise<PublicBetaTestimonial[]> {
  const { data, error } = await supabase.rpc("list_public_beta_testimonials")

  if (error) {
    console.error("[beta-testimonials] public fetch failed", error)
    return []
  }

  return (data as PublicBetaTestimonial[]) ?? []
}

export async function saveBetaTestimonial(
  userId: string,
  input: BetaTestimonialInput,
  existing: BetaTestimonialRow | null
): Promise<{ ok: true; row: BetaTestimonialRow } | { ok: false; message: string }> {
  const normalized = normalizeBetaTestimonialInput(input)

  if (!normalized.title || !normalized.review) {
    return { ok: false, message: "Title and review are required." }
  }

  if (existing) {
    const { data, error } = await supabase
      .from("beta_testimonials")
      .update(normalized)
      .eq("id", existing.id)
      .eq("user_id", userId)
      .select(BETA_TESTIMONIAL_SELECT)
      .single()

    if (error) {
      return { ok: false, message: error.message }
    }

    return { ok: true, row: data as BetaTestimonialRow }
  }

  const { data, error } = await supabase
    .from("beta_testimonials")
    .insert({
      user_id: userId,
      ...normalized,
    })
    .select(BETA_TESTIMONIAL_SELECT)
    .single()

  if (error) {
    if (error.code === "23505") {
      return {
        ok: false,
        message: "You already submitted a testimonial. Edit your existing one instead.",
      }
    }
    return { ok: false, message: error.message }
  }

  return { ok: true, row: data as BetaTestimonialRow }
}
