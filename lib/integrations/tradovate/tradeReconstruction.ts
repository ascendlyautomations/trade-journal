export type ReconstructionFill = {
  fillId: string
  contractId: string
  timestamp: string
  action: "Buy" | "Sell"
  qty: number
  price: number
  orderId?: string
}

export type ReconstructedLifecycleTrade = {
  lifecycleKey: string
  contractId: string
  direction: "Long" | "Short"
  contracts: number
  entryPrice: number
  exitPrice: number
  entryTime: string
  exitTime: string
  fillIds: string[]
  points: number
}

type OpenLifecycle = {
  direction: "Long" | "Short"
  entryValue: number
  entryQty: number
  exitValue: number
  exitQty: number
  entryTime: string
  exitTime: string
  fillIds: string[]
}

function signedDelta(action: "Buy" | "Sell", qty: number): number {
  return action === "Buy" ? qty : -qty
}

function directionalPoints(
  direction: "Long" | "Short",
  entryPrice: number,
  exitPrice: number
): number {
  if (direction === "Short") return entryPrice - exitPrice
  return exitPrice - entryPrice
}

function compareFills(a: ReconstructionFill, b: ReconstructionFill): number {
  const ta = new Date(a.timestamp).getTime()
  const tb = new Date(b.timestamp).getTime()
  if (ta !== tb) return ta - tb
  return a.fillId.localeCompare(b.fillId, undefined, { numeric: true })
}

export function buildBrokerLifecycleKey(
  provider: "tradovate" | "rithmic",
  brokerAccountScopeId: string,
  contractId: string,
  lifecycleIndex: number
): string {
  return `${provider}:v2:${brokerAccountScopeId}:${contractId}:${lifecycleIndex}`
}

export function buildTradovateLifecycleKey(
  brokerAccountScopeId: string,
  contractId: string,
  lifecycleIndex: number
): string {
  return buildBrokerLifecycleKey("tradovate", brokerAccountScopeId, contractId, lifecycleIndex)
}

export function buildRithmicLifecycleKey(
  brokerAccountScopeId: string,
  contractId: string,
  lifecycleIndex: number
): string {
  return buildBrokerLifecycleKey("rithmic", brokerAccountScopeId, contractId, lifecycleIndex)
}

/**
 * Flat-to-flat position lifecycle reconstruction for one instrument (contract id).
 * Supports scale in/out, partial fills, reversals, and multiple round trips.
 */
export function reconstructCompletedTradesForContract(
  fills: ReconstructionFill[],
  params: {
    /** Stable broker account scope — Tradovate/Rithmic external_account_id (not mapping uuid). */
    brokerAccountScopeId: string
    contractId: string
    lifecycleProvider?: "tradovate" | "rithmic"
  }
): { completed: ReconstructedLifecycleTrade[]; openSignedQty: number } {
  const lifecycleProvider = params.lifecycleProvider ?? "tradovate"
  const sorted = [...fills].sort(compareFills)
  let position = 0
  let lifecycleIndex = 0
  let current: OpenLifecycle | null = null
  const completed: ReconstructedLifecycleTrade[] = []

  function emitCompleted() {
    if (!current || current.exitQty <= 0) return
    const contracts = current.exitQty
    const entryPrice = current.entryValue / current.entryQty
    const exitPrice = current.exitValue / current.exitQty
    const direction = current.direction
    completed.push({
      lifecycleKey: buildBrokerLifecycleKey(
        lifecycleProvider,
        params.brokerAccountScopeId,
        params.contractId,
        lifecycleIndex
      ),
      contractId: params.contractId,
      direction,
      contracts,
      entryPrice,
      exitPrice,
      entryTime: current.entryTime,
      exitTime: current.exitTime,
      fillIds: [...current.fillIds],
      points: directionalPoints(direction, entryPrice, exitPrice),
    })
    current = null
  }

  function openLifecycle(sign: 1 | -1, qty: number, price: number, fill: ReconstructionFill) {
    lifecycleIndex += 1
    current = {
      direction: sign > 0 ? "Long" : "Short",
      entryValue: price * qty,
      entryQty: qty,
      exitValue: 0,
      exitQty: 0,
      entryTime: fill.timestamp,
      exitTime: fill.timestamp,
      fillIds: [fill.fillId],
    }
    position = sign * qty
  }

  for (const fill of sorted) {
    if (!Number.isFinite(fill.qty) || fill.qty <= 0) continue
    let remaining = signedDelta(fill.action, fill.qty)

    while (remaining !== 0) {
      if (position === 0) {
        const qty = Math.abs(remaining)
        openLifecycle(remaining > 0 ? 1 : -1, qty, fill.price, fill)
        remaining = 0
        continue
      }

      const posSign = Math.sign(position) as 1 | -1
      const remSign = Math.sign(remaining) as 1 | -1

      if (posSign === remSign) {
        const open = current as OpenLifecycle | null
        if (position === 0 || !open) break
        const addQty = Math.abs(remaining)
        open.entryValue += fill.price * addQty
        open.entryQty += addQty
        open.fillIds.push(fill.fillId)
        position += remaining
        remaining = 0
        continue
      }

      const closeQty = Math.min(Math.abs(position), Math.abs(remaining))
      const closing = current as OpenLifecycle | null
      if (!closing) break
      closing.exitValue += fill.price * closeQty
      closing.exitQty += closeQty
      closing.exitTime = fill.timestamp
      closing.fillIds.push(fill.fillId)
      position += posSign * -closeQty
      remaining += posSign * closeQty

      if (position === 0) {
        emitCompleted()
      }

      if (remaining !== 0 && position === 0) {
        const qty = Math.abs(remaining)
        openLifecycle(remaining > 0 ? 1 : -1, qty, fill.price, fill)
        remaining = 0
      }
    }
  }

  return { completed, openSignedQty: position }
}

export function reconstructAllCompletedTrades(
  fills: ReconstructionFill[],
  brokerAccountScopeId: string,
  options?: { lifecycleProvider?: "tradovate" | "rithmic" }
): {
  completed: ReconstructedLifecycleTrade[]
  openByContract: Map<string, number>
} {
  const dedupedByFillId = new Map<string, ReconstructionFill>()
  for (const fill of fills) {
    dedupedByFillId.set(fill.fillId, fill)
  }
  const uniqueFills = [...dedupedByFillId.values()]

  const byContract = new Map<string, ReconstructionFill[]>()
  for (const fill of uniqueFills) {
    const list = byContract.get(fill.contractId) ?? []
    list.push(fill)
    byContract.set(fill.contractId, list)
  }

  const completed: ReconstructedLifecycleTrade[] = []
  const openByContract = new Map<string, number>()

  for (const [contractId, contractFills] of byContract) {
    const result = reconstructCompletedTradesForContract(contractFills, {
      brokerAccountScopeId,
      contractId,
      lifecycleProvider: options?.lifecycleProvider,
    })
    completed.push(...result.completed)
    if (result.openSignedQty !== 0) {
      openByContract.set(contractId, result.openSignedQty)
    }
  }

  completed.sort(
    (a, b) => new Date(a.entryTime).getTime() - new Date(b.entryTime).getTime()
  )
  return { completed, openByContract }
}

export function computeFuturesGrossPnl(
  direction: "Long" | "Short",
  entryPrice: number,
  exitPrice: number,
  contracts: number,
  valuePerPoint: number
): number {
  const points = directionalPoints(direction, entryPrice, exitPrice)
  return points * valuePerPoint * contracts
}

export function sumFillFees(
  feesByFillId: Map<
    string,
    { clearingFee: number; exchangeFee: number; nfaFee: number; commission?: number }
  >,
  fillIds: string[]
): number {
  let total = 0
  for (const id of fillIds) {
    const row = feesByFillId.get(id)
    if (!row) continue
    total +=
      row.clearingFee +
      row.exchangeFee +
      row.nfaFee +
      (row.commission ?? 0)
  }
  return total
}
