import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { USER_FACING_ERROR_MESSAGES, toUserFacingErrorMessage } from "@/lib/userFacingError"

const AUTHORIZE_PATH = "/api/integrations/tradovate/authorize"

/**
 * Starts Tradovate OAuth via top-level browser navigation (never fetch-follows Tradovate redirect).
 *
 * 1. POST handoff cookie using Bearer session (localStorage Supabase auth).
 * 2. Navigate to GET authorize; server redirects to Tradovate as a normal document navigation.
 */
export async function startTradovateOAuthConnect(): Promise<void> {
  const headers = await supabaseBearerHeaders()
  if (!("Authorization" in headers)) {
    throw new Error(USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED)
  }

  const res = await fetch(AUTHORIZE_PATH, {
    method: "POST",
    headers: {
      ...headers,
      Accept: "application/json",
    },
    credentials: "same-origin",
  })

  if (res.status === 401 || res.status === 403) {
    throw new Error(USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED)
  }

  if (!res.ok) {
    let message = "Could not start Tradovate connection. Please try again."
    try {
      const body = (await res.json()) as { error?: string }
      if (body?.error) {
        message = toUserFacingErrorMessage(body.error, message)
      }
    } catch {
      // ignore
    }
    throw new Error(message)
  }

  window.location.assign(AUTHORIZE_PATH)
}
