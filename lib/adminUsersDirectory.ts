import type { SupabaseClient } from "@supabase/supabase-js"

export type AdminUserListRow = {
  id: string
  username: string
  name: string
  email: string
  avatar_url: string | null
  created_at: string
  is_private: boolean
  is_pro: boolean
  subscription_status: string
  referral_code: string
  is_banned: boolean
  banned_reason: string | null
  banned_at: string | null
  is_beta_tester: boolean
  full_count: number
}

function parseDirectoryCount(raw: Record<string, unknown>): number {
  const v = raw.full_count ?? raw.total_count ?? raw.fullCount ?? raw.totalCount
  if (typeof v === "number" && Number.isFinite(v)) return v
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v)
    if (Number.isFinite(n)) return n
  }
  return 0
}

export async function fetchAdminUserDirectory(
  supabase: SupabaseClient,
  input: {
    search: string
    banned: "all" | "banned" | "active"
    pro: "all" | "pro" | "non_pro"
    privacy: "all" | "private" | "public"
    limit?: number
    offset?: number
  }
): Promise<{ rows: AdminUserListRow[]; total: number; error: Error | null }> {
  const searchTrim = input.search.trim()
  /** RPC expects boolean | null (null = no filter). */
  const pBanned = input.banned === "all" ? null : input.banned === "banned"
  const pPro = input.pro === "all" ? null : input.pro === "pro"
  const pPrivate = input.privacy === "all" ? null : input.privacy === "private"

  const rpcArgs = {
    p_search: searchTrim === "" ? null : searchTrim,
    p_banned: pBanned,
    p_pro: pPro,
    p_private: pPrivate,
    p_limit: input.limit ?? 20,
    p_offset: input.offset ?? 0,
  }

  if (process.env.NODE_ENV !== "production") {
    console.debug("[admin/users] admin_list_users params", rpcArgs)
  }

  const { data, error } = await supabase.rpc("admin_list_users", rpcArgs)

  if (error) {
    return { rows: [], total: 0, error: new Error(error.message) }
  }

  let rowsRaw: unknown = data
  if (typeof data === "string") {
    try {
      rowsRaw = JSON.parse(data)
    } catch {
      rowsRaw = []
    }
  }

  if (!Array.isArray(rowsRaw) || rowsRaw.length === 0) {
    return { rows: [], total: 0, error: null }
  }

  const rows: AdminUserListRow[] = rowsRaw.map((raw) => {
    const o = raw as Record<string, unknown>
    return {
      id: String(o.id ?? ""),
      username: String(o.username ?? ""),
      name: String(o.name ?? ""),
      email: String(o.email ?? ""),
      avatar_url: o.avatar_url != null ? String(o.avatar_url) : null,
      created_at: String(o.created_at ?? ""),
      is_private: Boolean(o.is_private),
      is_pro: Boolean(o.is_pro),
      subscription_status: String(o.subscription_status ?? ""),
      referral_code: String(o.referral_code ?? ""),
      is_banned: Boolean(o.is_banned),
      banned_reason: o.banned_reason != null ? String(o.banned_reason) : null,
      banned_at: o.banned_at != null ? String(o.banned_at) : null,
      is_beta_tester: Boolean(o.is_beta_tester),
      full_count: parseDirectoryCount(o),
    }
  })

  const total = rows.length > 0 ? parseDirectoryCount(rowsRaw[0] as Record<string, unknown>) : 0
  return { rows, total, error: null }
}

export type AdminUserActivityCounts = {
  trades: number
  posts: number
  achievements: number
  feedback: number
  /** Matches RPC key `supportTickets` */
  supportTickets: number
}

export async function fetchUserActivityCounts(
  supabase: SupabaseClient,
  userId: string
): Promise<{ data: AdminUserActivityCounts; error: Error | null }> {
  const { data, error } = await supabase.rpc("admin_user_activity_counts", { p_target: userId })

  if (error) {
    return {
      data: { trades: 0, posts: 0, achievements: 0, feedback: 0, supportTickets: 0 },
      error: new Error(error.message),
    }
  }

  let parsed: unknown = data
  if (typeof data === "string") {
    try {
      parsed = JSON.parse(data)
    } catch {
      return {
        data: { trades: 0, posts: 0, achievements: 0, feedback: 0, supportTickets: 0 },
        error: new Error("Invalid count response (JSON)"),
      }
    }
  }

  const j = parsed as Record<string, unknown> | null
  if (!j || typeof j !== "object") {
    return {
      data: { trades: 0, posts: 0, achievements: 0, feedback: 0, supportTickets: 0 },
      error: new Error("Invalid count response"),
    }
  }

  const n = (v: unknown) => {
    if (typeof v === "number" && Number.isFinite(v)) return v
    if (typeof v === "string" && v.trim() !== "") {
      const x = Number(v)
      if (Number.isFinite(x)) return x
    }
    return 0
  }

  if (process.env.NODE_ENV !== "production") {
    console.debug("[admin/users] admin_user_activity_counts raw", parsed)
  }

  return {
    data: {
      trades: n(j.trades),
      posts: n(j.posts),
      achievements: n(j.achievements),
      feedback: n(j.feedback),
      supportTickets: n(j.supportTickets ?? j.support),
    },
    error: null,
  }
}
