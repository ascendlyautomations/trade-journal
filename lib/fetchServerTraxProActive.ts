/** Returns the server entitlement, or null when the request cannot be trusted. */
export async function fetchServerTraxProActive(): Promise<boolean | null> {
  try {
    const response = await fetch("/api/billing/entitlement", {
      credentials: "same-origin",
      cache: "no-store",
    })
    if (!response.ok) return null
    const body = (await response.json()) as { traxProActive?: unknown }
    if (typeof body.traxProActive !== "boolean") return null
    return body.traxProActive
  } catch {
    return null
  }
}
