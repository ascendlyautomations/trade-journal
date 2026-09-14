import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { USER_FACING_ERROR_MESSAGES } from "@/lib/userFacingError"

/**
 * Starts Tradovate OAuth using the server authorize route (Bearer session required).
 */
export async function startTradovateOAuthConnect(): Promise<void> {
  const headers = await supabaseBearerHeaders()
  if (!("Authorization" in headers)) {
    throw new Error(USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED)
  }

  const res = await fetch("/api/integrations/tradovate/authorize", {
    method: "GET",
    headers,
    redirect: "manual",
    credentials: "same-origin",
  })

  if (res.status === 401 || res.status === 403) {
    throw new Error(USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED)
  }

  if (res.status === 302 || res.status === 307 || res.status === 308) {
    const location = res.headers.get("Location")
    if (!location) {
      throw new Error("Could not start Tradovate connection. Please try again.")
    }
    window.location.assign(location)
    return
  }

  if (!res.ok) {
    let message = "Could not start Tradovate connection. Please try again."
    try {
      const body = (await res.json()) as { error?: string }
      if (body?.error) message = body.error
    } catch {
      // ignore
    }
    throw new Error(message)
  }

  throw new Error("Could not start Tradovate connection. Please try again.")
}
