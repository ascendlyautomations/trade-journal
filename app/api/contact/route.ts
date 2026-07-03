import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  PUBLIC_CONTACT_CATEGORY_LABELS,
  PUBLIC_CONTACT_SUBJECTS,
  publicContactAdminType,
  type PublicContactCategory,
} from "@/lib/publicContact"
import { profilePath } from "@/lib/profileRoutes"
import { sendAdminSubmissionEmail } from "@/lib/server/sendAdminSubmissionEmail"
import { SITE_URL } from "@/lib/site"

const VALID_CATEGORIES = new Set<PublicContactCategory>([
  "general",
  "billing",
  "partnership",
  "business",
])

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export async function POST(req: Request) {
  let body: {
    category?: string
    name?: string
    email?: string
    subject?: string
    message?: string
  }

  try {
    body = (await req.json()) as typeof body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const category = body.category as PublicContactCategory | undefined
  const name = body.name?.trim() ?? ""
  const email = body.email?.trim() ?? ""
  const subject = body.subject?.trim() ?? ""
  const message = body.message?.trim() ?? ""

  if (!category || !VALID_CATEGORIES.has(category)) {
    return Response.json({ error: "Invalid contact category" }, { status: 400 })
  }

  if (!name || name.length > 200) {
    return Response.json({ error: "Name is required" }, { status: 400 })
  }

  if (!email || !EMAIL_RE.test(email) || email.length > 320) {
    return Response.json({ error: "A valid email is required" }, { status: 400 })
  }

  const expectedSubject = PUBLIC_CONTACT_SUBJECTS[category]
  if (subject !== expectedSubject) {
    return Response.json({ error: "Invalid subject for category" }, { status: 400 })
  }

  if (!message || message.length > 5000) {
    return Response.json({ error: "Message is required" }, { status: 400 })
  }

  const user = await getRouteUser(req)

  let username: string | null = null
  const registeredEmail = user?.email?.trim() ?? null

  if (user?.id) {
    const { data: profileRow } = await supabaseServiceRole
      .from("profiles")
      .select("username")
      .eq("id", user.id)
      .maybeSingle()

    username = profileRow?.username?.trim() ?? null
  }

  const { data, error } = await supabaseServiceRole
    .from("public_contact_submissions")
    .insert({
      user_id: user?.id ?? null,
      name,
      email,
      category,
      subject,
      message,
    })
    .select("id, created_at")
    .single()

  if (error || !data) {
    console.error("[api/contact] insert failed", error)
    return Response.json({ error: "Failed to submit message" }, { status: 500 })
  }

  const adminType = publicContactAdminType(category)
  const profileUrl =
    user?.id != null
      ? `${SITE_URL}${profilePath({ username, id: user.id })}`
      : null

  const emailResult = await sendAdminSubmissionEmail({
    type: adminType,
    recordId: data.id,
    userId: user?.id ?? "public",
    userEmail: email,
    registeredEmail,
    username,
    displayName: name,
    createdAt: data.created_at,
    category: PUBLIC_CONTACT_CATEGORY_LABELS[category],
    description: message,
    subjectOverride: subject,
    adminUrl: `${SITE_URL}/contact`,
    profileUrl,
  })

  if (!emailResult.ok && !emailResult.skipped) {
    console.error("[api/contact] email failed", {
      recordId: data.id,
      error: emailResult.error,
    })
  }

  return Response.json({ ok: true, emailSent: emailResult.ok })
}
