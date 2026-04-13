import { supabase } from "./supabaseClient"

/** Upload to public `avatars` bucket; returns public URL or null on failure. */
export async function uploadAvatarFile(
  userId: string,
  file: File
): Promise<string | null> {
  const fileExt = file.name.split(".").pop()
  const fileName = `${userId}/${Date.now()}.${fileExt}`

  const { error } = await supabase.storage
    .from("avatars")
    .upload(fileName, file, { upsert: true })

  if (error) {
    console.error("Avatar upload error:", error.message)
    return null
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  return `${base}/storage/v1/object/public/avatars/${fileName}`
}
