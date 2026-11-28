import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import type { AiMessageAttachment } from "@/lib/server/ai/aiConversationTypes"

export const AI_COACH_ATTACHMENTS_BUCKET = "ai-coach-attachments"

const MAX_BYTES = 10 * 1024 * 1024

export async function uploadAiCoachAttachment(
  db: SupabaseClient<Database>,
  userId: string,
  bytes: Buffer,
  contentType: string,
  conversationId?: string | null
): Promise<{ attachment: AiMessageAttachment; error?: string }> {
  if (bytes.byteLength > MAX_BYTES) {
    return { attachment: { kind: "uploaded_image", url: "", storagePath: null }, error: "file_too_large" }
  }
  const folder = conversationId?.trim() || "draft"
  const path = `${userId}/${folder}/${crypto.randomUUID()}.${extensionForMime(contentType)}`

  const { error } = await db.storage.from(AI_COACH_ATTACHMENTS_BUCKET).upload(path, bytes, {
    contentType,
    upsert: false,
  })
  if (error) {
    return { attachment: { kind: "uploaded_image", url: "", storagePath: null }, error: error.message }
  }

  const { data: signed, error: signErr } = await db.storage
    .from(AI_COACH_ATTACHMENTS_BUCKET)
    .createSignedUrl(path, 60 * 30)

  if (signErr || !signed?.signedUrl) {
    return { attachment: { kind: "uploaded_image", url: "", storagePath: path }, error: signErr?.message ?? "sign_failed" }
  }

  return {
    attachment: {
      kind: "uploaded_image",
      url: signed.signedUrl,
      storagePath: path,
    },
  }
}

export async function signedUrlsForAttachments(
  db: SupabaseClient<Database>,
  attachments: AiMessageAttachment[]
): Promise<string[]> {
  const urls: string[] = []
  for (const item of attachments) {
    if (item.url?.startsWith("http")) {
      urls.push(item.url)
      continue
    }
    if (item.storagePath) {
      const { data } = await db.storage
        .from(AI_COACH_ATTACHMENTS_BUCKET)
        .createSignedUrl(item.storagePath, 60 * 30)
      if (data?.signedUrl) urls.push(data.signedUrl)
    }
  }
  return urls
}

function extensionForMime(mime: string): string {
  switch (mime) {
    case "image/png":
      return "png"
    case "image/webp":
      return "webp"
    case "image/heic":
      return "heic"
    default:
      return "jpg"
  }
}