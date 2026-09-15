const MAX_RP_CODE_LEN = 240

/** Safe client-facing Rithmic rp_code / user_msg fragments (no credentials). */
export function safeRpCodeForClient(rpCode: string[] | undefined): string[] {
  if (!rpCode?.length) return []
  return rpCode.map((entry) => {
    if (entry === "0") return "0"
    const trimmed = entry.trim().slice(0, MAX_RP_CODE_LEN)
    if (!trimmed) return "(empty)"
    const lower = trimmed.toLowerCase()
    if (lower.includes("password") || lower.includes("credential")) {
      return "(redacted)"
    }
    return trimmed
  })
}
