import type { User } from "@supabase/supabase-js"

/** Best-effort signup/auth provider label for admin beta signup emails. */
export function resolveSignupMethodLabel(
  user: User,
  context?: "beta_repair"
): string {
  if (context === "beta_repair") {
    return "google_oauth (beta repair)"
  }

  const provider = user.app_metadata?.provider
  if (provider === "google") return "google_oauth"
  if (typeof provider === "string" && provider.trim()) return provider
  return "email"
}
