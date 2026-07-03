import type { SupabaseClient } from "@supabase/supabase-js"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { validateImageUpload } from "@/lib/uploadValidation"

export async function publishStory(
  supabase: SupabaseClient,
  userId: string,
  file: File
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (!userId || !file) {
    return { ok: false, message: "Missing story image" }
  }

  const validationError = validateImageUpload(file)
  if (validationError) {
    return { ok: false, message: validationError }
  }

  const fileName = `${userId}/${Date.now()}-${file.name}`

  const { error: uploadError } = await supabase.storage
    .from("stories")
    .upload(fileName, file, { upsert: true })

  if (uploadError) {
    console.error("[publishStory] upload failed", uploadError)
    return { ok: false, message: uploadError.message }
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) {
    return { ok: false, message: "Missing NEXT_PUBLIC_SUPABASE_URL" }
  }

  const publicUrl = `${base}/storage/v1/object/public/stories/${fileName}`

  const { error: insertError } = await supabase.from("stories").insert({
    user_id: userId,
    image_url: publicUrl,
  })

  if (insertError) {
    console.error("[publishStory] insert failed", insertError)
    return { ok: false, message: handleSupabaseError(insertError) }
  }

  return { ok: true }
}
