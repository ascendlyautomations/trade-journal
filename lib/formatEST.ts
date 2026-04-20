export function formatEST(dateString: string) {
  if (!dateString) return ""

  const isoString = dateString.includes("Z")
    ? dateString
    : dateString + "Z"

  return new Date(isoString).toLocaleString("en-US", {
    timeZone: "America/New_York",
    month: "numeric",
    day: "numeric",
    year: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })
}
