/** Strip spreadsheet formula injection prefixes from imported CSV text fields. */
export function sanitizeCsvTextField(value: string): string {
  const trimmed = value.trim()
  if (!trimmed) return trimmed

  if (/^[=+\-@]/.test(trimmed)) {
    return `'${trimmed}`
  }

  return trimmed
}
