import type { SupabaseClient } from "@supabase/supabase-js"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import type { UploadProgressReporter } from "@/lib/uploadProgress/types"
import { handleSupabaseError } from "@/lib/handleSupabaseError"

export type ContentDraftType = "trade" | "post" | "achievement" | "story"

export type SaveContentDraftInput = {
  userId: string
  draftId: string
  draftType: ContentDraftType
  payload: Record<string, unknown>
  /** Optional image bytes for draft-media storage (private bucket). */
  imageFile?: File | Blob | null
  imageContentType?: string
  previousMediaPaths?: string[]
}

export type SaveContentDraftResult =
  | { ok: true; draftId: string }
  | { ok: false; message: string }

async function uploadDraftImageWithProgress(
  supabase: SupabaseClient,
  input: {
    userId: string
    draftId: string
    file: File | Blob
    contentType: string
  },
  report: UploadProgressReporter
): Promise<{ path: string | null; error: string | null }> {
  const path = `${input.userId}/${input.draftId}/image.jpg`
  report({ percent: 10, stage: "Preparing draft…" })
  report({ percent: 18, stage: "Uploading media…" })
  const mediaReport = createMonotonicReporter(report, { min: 18, max: 72 })
  const { uploadToSupabaseStorageWithProgress } = await import(
    "@/lib/supabaseStorageUploadWithProgress"
  )
  const { error } = await uploadToSupabaseStorageWithProgress(supabase, {
    bucket: "draft-media",
    path,
    file: input.file,
    upsert: true,
    cacheControl: "private, max-age=0",
    onProgress: (loaded, total) => {
      mediaReport({
        percent: mapUploadBytesToPercent(loaded, total, { start: 20, end: 72 }),
        stage: "Uploading media…",
      })
    },
  })
  if (error) return { path: null, error }
  return { path, error: null }
}

/** Persists a private composer draft with the same upload % stages as publish flows. */
export async function saveContentDraft(
  supabase: SupabaseClient,
  input: SaveContentDraftInput,
  report: UploadProgressReporter
): Promise<SaveContentDraftResult> {
  const payload: Record<string, unknown> = { version: 1, ...input.payload }

  if (input.imageFile) {
    const contentType = input.imageContentType ?? "image/jpeg"
    const uploaded = await uploadDraftImageWithProgress(
      supabase,
      {
        userId: input.userId,
        draftId: input.draftId,
        file: input.imageFile,
        contentType,
      },
      report
    )
    if (uploaded.error) {
      return { ok: false, message: uploaded.error }
    }
    if (uploaded.path) {
      const key =
        input.draftType === "trade"
          ? "trade"
          : input.draftType === "post"
            ? "post"
            : input.draftType === "achievement"
              ? "achievement"
              : "story"
      const section = (payload[key] as Record<string, unknown> | undefined) ?? {}
      section.imageStoragePath = uploaded.path
      payload[key] = section
    }
  }

  report({ percent: 82, stage: "Saving draft…" })

  const { error } = await supabase.from("content_drafts").upsert(
    {
      id: input.draftId,
      user_id: input.userId,
      draft_type: input.draftType,
      payload,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "id" }
  )

  if (error) {
    return { ok: false, message: handleSupabaseError(error) }
  }

  report({ percent: 95, stage: "Finishing…" })
  return { ok: true, draftId: input.draftId }
}
