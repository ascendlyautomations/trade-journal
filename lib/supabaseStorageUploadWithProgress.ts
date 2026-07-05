import type { SupabaseClient } from "@supabase/supabase-js"

export type SupabaseStorageUploadOptions = {
  bucket: string
  path: string
  file: File | Blob
  contentType?: string
  upsert?: boolean
  onProgress?: (loaded: number, total: number) => void
}

function encodeStoragePath(path: string): string {
  return path
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/")
}

/** Upload via XHR so byte progress events are available (Supabase JS client has none). */
export async function uploadToSupabaseStorageWithProgress(
  supabase: SupabaseClient,
  options: SupabaseStorageUploadOptions
): Promise<{ error: string | null }> {
  const {
    data: { session },
  } = await supabase.auth.getSession()

  const token = session?.access_token
  const apiKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL

  if (!token) return { error: "Not authenticated." }
  if (!apiKey || !base) return { error: "Missing storage configuration." }

  const encodedPath = encodeStoragePath(options.path.replace(/^\/+/, ""))
  const url = `${base}/storage/v1/object/${options.bucket}/${encodedPath}`

  return new Promise((resolve) => {
    const xhr = new XMLHttpRequest()
    xhr.open("POST", url)
    xhr.setRequestHeader("Authorization", `Bearer ${token}`)
    xhr.setRequestHeader("apikey", apiKey)
    xhr.setRequestHeader(
      "Content-Type",
      options.contentType ||
        (options.file instanceof File
          ? options.file.type
          : "application/octet-stream") ||
        "application/octet-stream"
    )
    if (options.upsert) {
      xhr.setRequestHeader("x-upsert", "true")
    }

    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        options.onProgress?.(event.loaded, event.total)
      }
    }

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve({ error: null })
        return
      }

      try {
        const body = JSON.parse(xhr.responseText) as {
          message?: string
          error?: string
        }
        resolve({
          error:
            body.message ||
            body.error ||
            `Upload failed (${xhr.status}).`,
        })
      } catch {
        resolve({ error: `Upload failed (${xhr.status}).` })
      }
    }

    xhr.onerror = () => resolve({ error: "Network error during upload." })
    xhr.onabort = () => resolve({ error: "Upload cancelled." })
    xhr.send(options.file)
  })
}
