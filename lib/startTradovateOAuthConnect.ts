import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { USER_FACING_ERROR_MESSAGES, toUserFacingErrorMessage } from "@/lib/userFacingError"

const AUTHORIZE_PATH = "/api/integrations/tradovate/authorize"

export type StartTradovateOAuthConnectOptions = {
  /** Reconnect an existing Tradovate connection (same provider identity required). */
  reconnectConnectionId?: string
}

export async function startTradovateOAuthConnect(
  options: StartTradovateOAuthConnectOptions = {}
): Promise<void> {
  const headers = await supabaseBearerHeaders()
  if (!("Authorization" in headers)) {
    throw new Error(USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED)
  }

  const res = await fetch(AUTHORIZE_PATH, {
    method: "POST",
    headers: {
      ...headers,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    credentials: "same-origin",
    body: JSON.stringify({
      reconnectConnectionId: options.reconnectConnectionId ?? undefined,
    }),
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
