import type { SupabaseClient } from "@supabase/supabase-js"
import { isUniqueViolation } from "@/lib/optimisticMutation"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { PROFILE_WALL_POST_SELECT } from "@/lib/profileWallPosts"

export type ProfileWallPostInsertPayload = Record<string, unknown> & {
  user_id: string
  client_publish_id: string
}

function isAmbiguousClientFailure(error: unknown): boolean {
  if (!error || typeof error !== "object") return false
  const message = String((error as { message?: string }).message ?? error)
  if (/fetch failed|network|timeout|aborted|failed to fetch/i.test(message)) {
    return true
  }
  return false
}

async function loadPostByClientPublishId(
  client: SupabaseClient,
  userId: string,
  clientPublishId: string
) {
  const { data, error } = await client
    .from("profile_posts")
    .select(PROFILE_WALL_POST_SELECT)
    .eq("user_id", userId)
    .eq("client_publish_id", clientPublishId)
    .maybeSingle()

  if (error) {
    return { post: null as Record<string, unknown> | null, error: handleSupabaseError(error) }
  }
  if (!data) {
    return { post: null, error: "Published post could not be verified." }
  }
  return { post: data as Record<string, unknown>, error: null as string | null }
}

/**
 * Insert a profile wall post with client_publish_id idempotency (matches iOS GlobalUpload job id).
 */
export async function insertProfileWallPostIdempotent(
  client: SupabaseClient,
  payload: ProfileWallPostInsertPayload
): Promise<
  | { ok: true; post: Record<string, unknown> }
  | { ok: false; message: string }
> {
  const userId = payload.user_id
  const clientPublishId = payload.client_publish_id

  const { data: idRow, error: insertError } = await client
    .from("profile_posts")
    .insert(payload)
    .select("id")
    .single()

  if (!insertError && idRow?.id) {
    const { data: created, error: loadError } = await client
      .from("profile_posts")
      .select(PROFILE_WALL_POST_SELECT)
      .eq("id", idRow.id)
      .single()

    if (loadError) {
      if (isAmbiguousClientFailure(loadError)) {
        const recovered = await loadPostByClientPublishId(
          client,
          userId,
          clientPublishId
        )
        if (recovered.post) {
          return { ok: true, post: recovered.post }
        }
      }
      return { ok: false, message: handleSupabaseError(loadError) }
    }
    if (!created) {
      return { ok: false, message: "Post insert returned no row" }
    }
    return { ok: true, post: created as Record<string, unknown> }
  }

  if (insertError && (isUniqueViolation(insertError) || isAmbiguousClientFailure(insertError))) {
    const recovered = await loadPostByClientPublishId(
      client,
      userId,
      clientPublishId
    )
    if (recovered.post) {
      return { ok: true, post: recovered.post }
    }
    if (recovered.error && !isUniqueViolation(insertError)) {
      return { ok: false, message: recovered.error }
    }
  }

  if (insertError) {
    return { ok: false, message: handleSupabaseError(insertError) }
  }

  const recovered = await loadPostByClientPublishId(
    client,
    userId,
    clientPublishId
  )
  if (recovered.post) {
    return { ok: true, post: recovered.post }
  }

  return { ok: false, message: recovered.error ?? "Post insert returned no row" }
}
