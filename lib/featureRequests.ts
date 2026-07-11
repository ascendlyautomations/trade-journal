import { supabase } from "@/lib/supabaseClient"
import { notifyAdminSubmission } from "@/lib/notifyAdminSubmission"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

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

  const { data, error: insertError } = await supabase
    .from("feature_requests")
    .insert({
      user_id: userId,
      title,
      description,
    })
    .select("id")
    .single()

  if (insertError) {
    if (insertError.code === "23505") {
      return {
        ok: false,
        message: "You already submitted a feature request with this title.",
      }
    }
    console.error("[featureRequests] insert failed", insertError)
    return { ok: false, message: toUserFacingErrorMessage(insertError) }
  }

  if (data?.id) {
    notifyAdminSubmission("feature_request", data.id)
  }

  return { ok: true }
}
