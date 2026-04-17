/**
 * Parses broker/CSV numeric cells: currency, commas, parentheses (accounting negatives),
 * leading minus, unicode minus, spaces. Returns null when empty/invalid (not 0).
 */

export function parseCsvNumeric(raw: string | null | undefined): number | null {
  if (raw == null) return null
  let s = String(raw).trim()
  if (
    (s.startsWith('"') && s.endsWith('"')) ||
    (s.startsWith("'") && s.endsWith("'"))
  ) {
    s = s.slice(1, -1).trim()
  }
  if (s === "" || s === "-" || s === "—") return null

  let neg = false
  if (/^\(.*\)$/.test(s) || /^\$\(.*\)$/.test(s)) {
    neg = !neg
  }

  s = s.replace(/[()]/g, "").trim()

  if (s === "" || s === "$") return null
  if (s.startsWith("$") && s.length > 1) {
    s = s.slice(1)
  }

  s = s.replace(/\u2212/g, "-")
  s = s.replace(/\$/g, "").replace(/,/g, "").replace(/%/g, "")
  s = s.replace(/\s+/g, "")

  while (s.startsWith("-")) {
    neg = !neg
    s = s.slice(1)
  }
  if (s.startsWith("+")) s = s.slice(1)

  if (s === "" || s === ".") return null
  const n = Number(s)
  if (!Number.isFinite(n)) return null
  return neg ? -Math.abs(n) : Math.abs(n)
}
