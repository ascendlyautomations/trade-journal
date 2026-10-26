/**
 * Guards optimistic rollbacks so a slow failed request cannot revert a newer mutation.
 */

const epochByKey = new Map<string, number>()

export function beginSocialMutation(key: string): number {
  const next = (epochByKey.get(key) ?? 0) + 1
  epochByKey.set(key, next)
  return next
}

export function isSocialMutationCurrent(key: string, epoch: number): boolean {
  return epochByKey.get(key) === epoch
}

export function rollbackSocialMutationIfCurrent(
  key: string,
  epoch: number,
  rollback: () => void
): void {
  if (isSocialMutationCurrent(key, epoch)) rollback()
}

export function socialMutationKey(
  domain: string,
  ...parts: string[]
): string {
  return [domain, ...parts.map((p) => String(p).trim())].join(":")
}
