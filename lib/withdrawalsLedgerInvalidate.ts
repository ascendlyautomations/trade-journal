/** Bump when manual ledger rows change so dashboard live balance refetches. */

let generation = 0
const listeners = new Set<() => void>()

export function getWithdrawalsLedgerGeneration(): number {
  return generation
}

export function subscribeWithdrawalsLedger(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function invalidateWithdrawalsLedger(): void {
  generation += 1
  for (const listener of listeners) listener()
}
