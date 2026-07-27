import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { buildFeedDeepLinkHref } from "@/lib/feedDeepLink"

const FIXED_MILESTONES = [1, 5, 15, 25, 50, 100, 250, 500, 1000] as const

export type LikeMilestoneEntity =
  | { kind: "trade"; id: string }
  | { kind: "post"; id: string }
  | { kind: "profile_post"; id: string }
  | { kind: "achievement_post"; id: string }
  | { kind: "reel"; id: string }

function nounForKind(kind: LikeMilestoneEntity["kind"]): string {
  switch (kind) {
    case "trade":
      return "trade"
    case "reel":
      return "reel"
    case "achievement_post":
      return "achievement"
    case "post":
    case "profile_post":
    default:
      return "post"
  }
}

function likeTableForKind(kind: LikeMilestoneEntity["kind"]): {
  table: string
  column: string
} {
  switch (kind) {
    case "trade":
      return { table: "trade_likes", column: "trade_id" }
    case "post":
      return { table: "likes", column: "post_id" }
    case "profile_post":
      return { table: "profile_post_likes", column: "profile_post_id" }
    case "achievement_post":
      return { table: "achievement_post_likes", column: "achievement_post_id" }
    case "reel":
      return { table: "reel_likes", column: "reel_id" }
  }
}

/** Next milestone to announce for this exact count, or null if none. */
export function milestoneForCount(count: number): number | null {
  if (!Number.isFinite(count) || count < 1) return null
  if ((FIXED_MILESTONES as readonly number[]).includes(count)) return count
  if (count > 1000 && count % 1000 === 0) return count
  return null
}

function milestoneKey(entity: LikeMilestoneEntity, milestone: number): string {
  return `${entity.kind}:${entity.id}:${milestone}`
}

function deepLinkForEntity(entity: LikeMilestoneEntity): string {
  switch (entity.kind) {
    case "trade":
      return buildFeedDeepLinkHref({ kind: "trade", id: entity.id })
    case "reel":
      return buildFeedDeepLinkHref({ kind: "reel", id: entity.id })
    case "achievement_post":
      return buildFeedDeepLinkHref({ kind: "achievement", id: entity.id })
    case "post":
    case "profile_post":
      return buildFeedDeepLinkHref({ kind: "post", id: entity.id })
  }
}

function notificationTargetFields(entity: LikeMilestoneEntity): Record<string, string> {
  switch (entity.kind) {
    case "trade":
      return { trade_id: entity.id }
    case "post":
      return { post_id: entity.id }
    case "profile_post":
      return { profile_post_id: entity.id }
    case "achievement_post":
      return { achievement_post_id: entity.id }
    case "reel":
      return { reel_id: entity.id }
  }
}

/**
 * After a content like, optionally notify the owner that a like milestone was hit.
 * Skips comments. Dedupes via persisted like_milestone rows (not shown in Activity inbox).
 */
export async function maybeNotifyLikeMilestone(params: {
  ownerUserId: string
  actorUserId: string
  entity: LikeMilestoneEntity
}): Promise<void> {
  const { ownerUserId, actorUserId, entity } = params
  if (!ownerUserId || ownerUserId === actorUserId) return

  const { table, column } = likeTableForKind(entity.kind)
  const { count, error: countErr } = await supabaseServiceRole
    .from(table)
    .select("*", { count: "exact", head: true })
    .eq(column, entity.id)

  if (countErr) {
    console.error("[like-milestone] count failed", countErr)
    return
  }

  const milestone = milestoneForCount(count ?? 0)
  if (milestone == null) return

  const key = milestoneKey(entity, milestone)
  const { data: existing, error: existingErr } = await supabaseServiceRole
    .from("notifications")
    .select("id")
    .eq("user_id", ownerUserId)
    .eq("type", "like_milestone")
    .ilike("content", `%"milestone_key":"${key}"%`)
    .limit(1)

  if (existingErr) {
    console.error("[like-milestone] dedupe lookup failed", existingErr)
    return
  }
  if (existing && existing.length > 0) return

  const noun = nounForKind(entity.kind)
  const content = JSON.stringify({
    milestone_key: key,
    milestone,
    entity_kind: entity.kind,
    entity_id: entity.id,
    title: `Your ${noun} reached ${milestone.toLocaleString("en-US")} likes`,
    body: `More traders are engaging with your ${noun}.`,
    href: deepLinkForEntity(entity),
  })

  const { error: insertErr } = await supabaseServiceRole.from("notifications").insert({
    user_id: ownerUserId,
    sender_id: actorUserId,
    type: "like_milestone",
    content,
    read: false,
    ...notificationTargetFields(entity),
  })

  if (insertErr) {
    if (insertErr.code === "23505") return
    console.error("[like-milestone] insert failed", insertErr)
    return
  }

  const { scheduleIosPushDelivery } = await import(
    "@/lib/server/push/deliverPushNotification"
  )
  scheduleIosPushDelivery({
    recipientUserId: ownerUserId,
    type: "like_milestone",
    sender_id: actorUserId,
    content,
    prefsAlreadyChecked: true,
    ...notificationTargetFields(entity),
  })
}
