import { supabase } from "@/lib/supabaseClient"

export type FeatureRequestStatus = "open" | "planned" | "completed"

export const FEATURE_REQUEST_STATUS_OPTIONS: {
  value: FeatureRequestStatus
  label: string
}[] = [
  { value: "open", label: "Open" },
  { value: "planned", label: "Planned" },
  { value: "completed", label: "Completed" },
]

export type FeatureRequestRow = {
  id: string
  user_id: string
  title: string
  description: string
  status: FeatureRequestStatus
  created_at: string
}

export type SubmitFeatureRequestInput = {
  title: string
  description: string
}

export async function submitFeatureRequest(
  userId: string,
  input: SubmitFeatureRequestInput
): Promise<{ ok: true } | { ok: false; message: string }> {
  const title = input.title.trim()
  const description = input.description.trim()
  if (!title || !description) {
    return { ok: false, message: "Title and description are required." }
  }

  const { error: insertError } = await supabase.from("feature_requests").insert({
    user_id: userId,
    title,
    description,
  })

  if (insertError) {
    return { ok: false, message: insertError.message }
  }

  return { ok: true }
}
