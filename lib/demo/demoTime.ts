export function isoDemoDaysAgo(daysAgo: number, hour = 12): string {
  const d = new Date()
  d.setHours(hour, 0, 0, 0)
  d.setDate(d.getDate() - daysAgo)
  return d.toISOString()
}
