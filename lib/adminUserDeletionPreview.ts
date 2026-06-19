import type { SupabaseClient } from "@supabase/supabase-js"

export type AdminUserDeletionPreview = {
  userId: string
  username: string | null
  email: string | null
  createdAt: string | null
  lastLoginAt: string | null
  subscriptionStatus: string | null
  isBetaTester: boolean
  stripeCustomerId: string | null
  tradeCount: number
  postCount: number
  commentCount: number
  messageCount: number
  roomOwnershipCount: number
  followerCount: number
  affiliateStatus: string | null
}

async function countRows(
  supabase: SupabaseClient,
  table: string,
  column: string,
  value: string
): Promise<number> {
  const { count, error } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true })
    .eq(column, value)

  if (error) {
    console.error(`[adminUserDeletionPreview] count ${table}.${column}:`, error.message)
    return 0
  }
  return count ?? 0
}

async function countComments(supabase: SupabaseClient, userId: string): Promise<number> {
  const [postComments, tradeComments] = await Promise.all([
    countRows(supabase, "comments", "user_id", userId),
    countRows(supabase, "trade_comments", "user_id", userId),
  ])
  return postComments + tradeComments
}

async function countMessages(supabase: SupabaseClient, userId: string): Promise<number> {
  const [bySender, byUser] = await Promise.all([
    countRows(supabase, "messages", "sender_id", userId),
    countRows(supabase, "messages", "user_id", userId),
  ])
  return bySender + byUser
}

async function resolveAffiliateStatus(
  supabase: SupabaseClient,
  userId: string
): Promise<string | null> {
  const { data: affiliate } = await supabase
    .from("affiliates")
    .select("id, code")
    .eq("user_id", userId)
    .maybeSingle()

  if (affiliate?.id) return `Active (${affiliate.code})`

  const { data: application } = await supabase
    .from("affiliate_applications")
    .select("status")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (application?.status) return `Application: ${application.status}`
  return null
}

export async function fetchAdminUserDeletionPreview(
  supabase: SupabaseClient,
  userId: string
): Promise<{ preview: AdminUserDeletionPreview | null; error: string | null }> {
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select(
      "id, username, created_at, subscription_status, is_beta_tester, stripe_customer_id"
    )
    .eq("id", userId)
    .maybeSingle()

  if (profileError) {
    return { preview: null, error: profileError.message }
  }
  if (!profile?.id) {
    return { preview: null, error: "User not found" }
  }

  const { data: authData, error: authError } =
    await supabase.auth.admin.getUserById(userId)

  if (authError) {
    return { preview: null, error: authError.message }
  }

  const [
    tradeCount,
    postCount,
    commentCount,
    messageCount,
    roomOwnershipCount,
    followerCount,
    affiliateStatus,
  ] = await Promise.all([
    countRows(supabase, "trades", "user_id", userId),
    countRows(supabase, "posts", "user_id", userId),
    countComments(supabase, userId),
    countMessages(supabase, userId),
    countRows(supabase, "rooms", "owner_user_id", userId),
    countRows(supabase, "followers", "following_id", userId),
    resolveAffiliateStatus(supabase, userId),
  ])

  return {
    preview: {
      userId,
      username: profile.username ?? null,
      email: authData.user?.email ?? null,
      createdAt: profile.created_at ?? authData.user?.created_at ?? null,
      lastLoginAt: authData.user?.last_sign_in_at ?? null,
      subscriptionStatus: profile.subscription_status ?? null,
      isBetaTester: profile.is_beta_tester === true,
      stripeCustomerId: profile.stripe_customer_id ?? null,
      tradeCount,
      postCount,
      commentCount,
      messageCount,
      roomOwnershipCount,
      followerCount,
      affiliateStatus,
    },
    error: null,
  }
}
