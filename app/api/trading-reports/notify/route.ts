/** Trading report push is delivered by `/api/cron/weekly-trading-reports` only. */
export async function POST() {
  return Response.json(
    { error: "Trading report notifications are scheduled server-side." },
    { status: 403 }
  )
}
