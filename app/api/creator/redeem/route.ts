import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  CREATOR_ACCESS_INVALID_MESSAGE,
  normalizeCreatorAccessCode,
} from "@/lib/creatorAccess"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json(
      {
        error: "Unauthorized",
        message: "You must be signed in to redeem Creator Access.",
      },
      { status: 401 }
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json(
      { error: "Invalid request", message: "Invalid request body." },
      { status: 400 }
    )
  }

  const rawCode =
    body && typeof body === "object" && "code" in body
      ? (body as { code?: unknown }).code
      : undefined
  const code = normalizeCreatorAccessCode(
    typeof rawCode === "string" ? rawCode : ""
  )

  if (!code) {
    return Response.json(
      { error: "invalid_code", message: CREATOR_ACCESS_INVALID_MESSAGE },
      { status: 400 }
    )
  }

  const { data, error } = await supabaseServiceRole.rpc(
    "redeem_creator_access_code",
    {
      p_code: code,
      p_user_id: user.id,
    }
  )

  if (error) {
    console.error("[creator/redeem] rpc error:", {
      userId: user.id,
      code,
      message: error.message,
      details: error.details,
      hint: error.hint,
      codeName: error.code,
    })
    return Response.json(
      {
        error: "rpc_error",
        message:
          error.message || "Something went wrong redeeming Creator Access.",
        details: error.details ?? null,
        hint: error.hint ?? null,
      },
      { status: 500 }
    )
  }

  const result = String(data ?? "").trim()

  if (result === "ok" || result === "already") {
    const grantedAt = new Date().toISOString()
    return Response.json({
      ok: true,
      alreadyGranted: result === "already",
      result,
      // Client can apply entitlement immediately — no follow-up profile fetch.
      entitlement: {
        creator_access: true,
        creator_code: code,
        creator_granted_at: grantedAt,
        is_pro: true,
      },
    })
  }

  console.error("[creator/redeem] rejected:", {
    userId: user.id,
    code,
    result,
  })

  // Do not collapse exhausted / no_profile into invalid_code — the invite row may
  // be present and active; only the redeem slot / profile write failed.
  if (result === "exhausted") {
    return Response.json(
      {
        error: "code_exhausted",
        message:
          "This creator access code has already been fully redeemed.",
        result,
      },
      { status: 400 }
    )
  }

  if (result === "no_profile") {
    return Response.json(
      {
        error: "no_profile",
        message: "Profile not found for this account. Complete signup and try again.",
        result,
      },
      { status: 400 }
    )
  }

  return Response.json(
    {
      error: "invalid_code",
      message: CREATOR_ACCESS_INVALID_MESSAGE,
      result,
    },
    { status: 400 }
  )
}
