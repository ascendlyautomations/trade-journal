export function getSessionFromDate(dateInput: string | Date) {
  if (!dateInput) return null

  const d = new Date(dateInput)
  if (Number.isNaN(d.getTime())) return null

  const est = new Date(
    d.toLocaleString("en-US", { timeZone: "America/New_York" })
  )

  const hours = est.getHours()
  const minutes = est.getMinutes()
  const time = hours + minutes / 60

  if (time >= 18 || time < 2) return "Asia"
  if (time >= 2 && time < 8.5) return "London"
  if (time >= 8.5 && time < 16) return "NY"
  if (time >= 16 && time < 18) return "After"

  return null
}
