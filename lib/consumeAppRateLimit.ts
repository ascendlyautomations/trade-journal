import { supabase } from "@/lib/supabaseClient"
import { formatRateLimitExceededMessage, isRateLimitExceededError } from "@/lib/rateLimitErrors"

export type AppRateLimitAction = "csv_import"

const ACTION_MESSAGES: Record<AppRateLimitAction, string> = {
  csv_import: "Too many CSV imports. Try again in an hour.",
}

export async function consumeAppRateLimit(
  action: AppRateLimitAction
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { error } = await supabase.rpc("consume_app_rate_limit", {
    p_action: action,
  })

  if (error) {
    if (isRateLimitExceededError(error.message)) {
      return {
        ok: false,
        message: formatRateLimitExceededMessage(ACTION_MESSAGES[action]),
      }
    }
    return { ok: false, message: error.message || "Could not verify rate limit." }
  }

  return { ok: true }
}
