/** Avoid JSX newline gaps like "trader s" / "member s". */
export function countNoun(
  count: number,
  singular: string,
  plural = `${singular}s`
): string {
  const safe = Number.isFinite(count) ? count : 0
  return `${safe.toLocaleString()} ${safe === 1 ? singular : plural}`
}
