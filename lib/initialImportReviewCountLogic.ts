export function countUnreviewedInitialImportsFromTrades(
  trades: readonly unknown[] | null | undefined
): number {
  if (!trades?.length) return 0
  let count = 0
  for (const trade of trades) {
    if (
      trade &&
      typeof trade === "object" &&
      (trade as { is_initial_import?: boolean }).is_initial_import === true &&
      (trade as { reviewed?: boolean }).reviewed === false
    ) {
      count += 1
    }
  }
  return count
}
