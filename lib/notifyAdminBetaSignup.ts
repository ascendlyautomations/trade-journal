import { supabase } from "@/lib/supabaseClient"

const SESSION_GUARD_PREFIX = "beta-signup-notify:"

function devLog(message: string, data?: Record<string, unknown>) {
  if (process.env.NODE_ENV === "development") {
    if (data) console.log(message, data)
    else console.log(message)
  }
}

/** Fire-and-forget admin email when a user becomes a beta tester (never throws). */
export function notifyAdminBetaSignup(signupMethod?: string): void {
  void (async () => {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      const token = session?.access_token
      const userId = session?.user?.id
      if (!token || !userId) {
        devLog("[beta-signup-email] skipped notify: no session", { userId: userId ?? null })
        return
      }

      const guardKey = `${SESSION_GUARD_PREFIX}${userId}`
      if (typeof window !== "undefined" && sessionStorage.getItem(guardKey)) {
        devLog("[beta-signup-email] skipped notify: session guard", { userId })
        return
      }

      devLog("[beta-signup-email] attempting notify", {
        userId,
        signupMethod: signupMethod ?? null,
      })

      const res = await fetch("/api/admin-notify/beta-signup", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          signupMethod: signupMethod?.trim() || null,
        }),
      })

      let body: Record<string, unknown> = {}
      try {
        body = (await res.json()) as Record<string, unknown>
      } catch {
        body = {}
      }

      devLog("[beta-signup-email] notify response", {
        userId,
        status: res.status,
        ok: res.ok,
        body,
      })

      if (!res.ok) {
        console.error("[beta-signup-email] API failed", {
          userId,
          status: res.status,
          body,
        })
        return
      }

      if (body.emailSent === true && typeof window !== "undefined") {
        sessionStorage.setItem(guardKey, "1")
      }
    } catch (err) {
      console.error("[beta-signup-email] request failed", { err })
    }
  })()
}
