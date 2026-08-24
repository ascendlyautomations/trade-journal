import { supabase } from "./supabaseClient"
import { isDemoUserId } from "./demo/constants"
import { isBackendV2Enabled } from "./backendV2/flags.ts"
import { getSessionIsAdmin } from "./backendV2/sessionBootstrapCache.ts"

export async function isUserAdmin(userId: string | null | undefined): Promise<boolean> {
  if (!userId) return false
  if (isDemoUserId(userId)) return false
  if (isBackendV2Enabled("session")) {
    const fromSession = getSessionIsAdmin(userId)
    if (fromSession !== null) return fromSession
  }
  const { data, error } = await supabase
    .from("admin_users")
    .select("user_id, role")
    .eq("user_id", userId)
    .maybeSingle()
  if (error) {
    if (process.env.NODE_ENV !== "production") {
      console.debug("[admin-check][isUserAdmin] query error", {
        userId,
        message: error.message,
        code: error.code,
        details: error.details,
        hint: error.hint,
      })
    }
    return false
  }
  return Boolean(data?.user_id)
}

export async function isCurrentUserAdmin(
  userId?: string | null
): Promise<boolean> {
  if (userId !== undefined) {
    return isUserAdmin(userId)
  }
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()
  if (error || !user?.id) {
    if (process.env.NODE_ENV !== "production") {
      console.debug("[admin-check][isCurrentUserAdmin] auth lookup failed", {
        hasUser: Boolean(user?.id),
        message: error?.message,
      })
    }
    return false
  }
  if (isDemoUserId(user.id)) return false
  return isUserAdmin(user.id)
}

export type AdminCheckResult = {
  isAdmin: boolean
  userId: string | null
  email: string | null
  row: { user_id: string; role: string | null } | null
  error: {
    message: string
    code: string | null
    details: string | null
    hint: string | null
  } | null
}

export async function getAdminCheckResultForUser(
  userId: string | null | undefined,
  email?: string | null
): Promise<AdminCheckResult> {
  if (!userId) {
    return {
      isAdmin: false,
      userId: null,
      email: email ?? null,
      row: null,
      error: null,
    }
  }

  if (isDemoUserId(userId)) {
    return {
      isAdmin: false,
      userId,
      email: email ?? null,
      row: null,
      error: null,
    }
  }

  // Session bootstrap owns is_admin — avoid a second admin_users REST hit.
  if (isBackendV2Enabled("session")) {
    const fromSession = getSessionIsAdmin(userId)
    if (fromSession !== null) {
      return {
        isAdmin: fromSession,
        userId,
        email: email ?? null,
        row: fromSession
          ? { user_id: userId, role: "admin" }
          : null,
        error: null,
      }
    }
  }

  const { data, error } = await supabase
    .from("admin_users")
    .select("user_id, role")
    .eq("user_id", userId)
    .maybeSingle()

  return {
    isAdmin: Boolean(data?.user_id) && !error,
    userId,
    email: email ?? null,
    row: data ?? null,
    error: error
      ? {
          message: error.message,
          code: error.code ?? null,
          details: error.details ?? null,
          hint: error.hint ?? null,
        }
      : null,
  }
}

export async function getCurrentAdminCheckResult(
  userId?: string | null,
  email?: string | null
): Promise<AdminCheckResult> {
  if (userId !== undefined) {
    return getAdminCheckResultForUser(userId, email)
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user?.id) {
    return {
      isAdmin: false,
      userId: user?.id ?? null,
      email: user?.email ?? null,
      row: null,
      error: authError
        ? {
            message: authError.message,
            code: authError.code ?? null,
            details: null,
            hint: null,
          }
        : null,
    }
  }

  return getAdminCheckResultForUser(user.id, user.email)
}

