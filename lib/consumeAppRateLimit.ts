import { supabase } from "@/lib/supabaseClient"
import { isRateLimitExceededError } from "@/lib/rateLimitErrors"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export type AppRateLimitAction = "csv_import"

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
        message: toUserFacingErrorMessage(error),
      }
    }
    return { ok: false, message: toUserFacingErrorMessage(error) }
  }

  return { ok: true }
}
