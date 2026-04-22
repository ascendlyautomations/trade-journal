export function formatCurrency(value: number | null | undefined) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) {
    return "$0.00"
  }

  const numeric = Number(value)
  const abs = Math.abs(numeric)
  const formatted = abs.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })

  return numeric < 0 ? `-${formatted}` : formatted
}
