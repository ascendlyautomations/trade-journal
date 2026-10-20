"use client"

import { useMemo } from "react"
import {
  computePersonalDrawdownLimitBalanceLineY,
  parsePersonalDrawdownLimit,
  resolveDashboardLiveSingleAccountId,
} from "@/lib/dashboardLiveAccountValue"

export type DashboardPersonalDrawdownLimitLineState =
  | { visible: false }
  | { visible: true; status: "ready"; lineY: number }

type UseDashboardPersonalDrawdownLimitLineOptions = {
  userId: string | null | undefined
  accountFilter: string
  accountById: Record<
    string,
    { category?: unknown; mode?: unknown; account_size?: unknown } | null | undefined
  >
  propFirmAccountId: string | null | undefined
  drawdownLimit: number | null | undefined
}

export function useDashboardPersonalDrawdownLimitLine({
  userId,
  accountFilter,
  accountById,
  propFirmAccountId,
  drawdownLimit,
}: UseDashboardPersonalDrawdownLimitLineOptions): DashboardPersonalDrawdownLimitLineState {
  const accountId = useMemo(
    () =>
      resolveDashboardLiveSingleAccountId({
        userId,
        accountFilter,
        accountById,
        propFirmAccountId,
      }),
    [userId, accountFilter, accountById, propFirmAccountId]
  )

  const limit = parsePersonalDrawdownLimit(drawdownLimit)

  return useMemo((): DashboardPersonalDrawdownLimitLineState => {
    if (!accountId || limit == null) return { visible: false }
    const account = accountById[accountId]
    if (!account) return { visible: false }

    const lineY = computePersonalDrawdownLimitBalanceLineY(account, limit)
    if (!Number.isFinite(lineY)) {
      return { visible: false }
    }

    return { visible: true, status: "ready", lineY }
  }, [accountById, accountId, limit])
}
