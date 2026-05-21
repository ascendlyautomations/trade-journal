/** Strip to digits + one dot; max 2 decimal places (internal value for save). */
export function sanitizeDrawdownLimitInput(raw: string): string {
  let t = raw.replace(/[^0-9.]/g, "")
  const dot = t.indexOf(".")
  if (dot !== -1) {
    t = t.slice(0, dot + 1) + t.slice(dot + 1).replace(/\./g, "")
  }
  const [intPart = "", frac] = t.split(".")
  if (frac !== undefined) {
    return `${intPart}.${frac.slice(0, 2)}`
  }
  return intPart
}

export function finalizeDrawdownLimitInput(raw: string): string {
  let t = sanitizeDrawdownLimitInput(raw)
  if (t.endsWith(".")) t = t.slice(0, -1)
  return t
}

export function formatDrawdownLimitForDisplay(
  raw: string,
  focused: boolean
): string {
  const s = sanitizeDrawdownLimitInput(raw)
  if (focused) return s
  if (s === "" || s === ".") return ""
  const n = Number(s)
  if (!Number.isFinite(n) || n < 0) return ""
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(n)
}

export const DASHBOARD_GEAR_SECTION_TITLE =
  "text-xs md:text-sm text-gray-400 uppercase tracking-wide mb-2"
