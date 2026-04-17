import { supabase } from "./supabaseClient"

export async function isUserAdmin(userId: string | null | undefined): Promise<boolean> {
  if (!userId) return false
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

export async function isCurrentUserAdmin(): Promise<boolean> {
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

export async function getCurrentAdminCheckResult(): Promise<AdminCheckResult> {
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

  const { data, error } = await supabase
    .from("admin_users")
    .select("user_id, role")
    .eq("user_id", user.id)
    .maybeSingle()

  return {
    isAdmin: Boolean(data?.user_id) && !error,
    userId: user.id,
    email: user.email ?? null,
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

