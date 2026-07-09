import type { CopyTradingGroup } from "./copyTradingGroups"

export const COPY_GROUP_FILTER_PREFIX = "copygroup:"

export const MANAGE_COPY_GROUPS_SETTINGS_HREF =
  "/settings#copy-trading-groups" as const

export function copyGroupFilterValue(groupId: string): string {
  return `${COPY_GROUP_FILTER_PREFIX}${groupId}`
}

export function parseCopyGroupFilterValue(
  value: string | null | undefined
): string | null {
  if (!value || !value.startsWith(COPY_GROUP_FILTER_PREFIX)) return null
  const id = value.slice(COPY_GROUP_FILTER_PREFIX.length).trim()
  return id || null
}

export function isCopyGroupFilterValue(value: string | null | undefined): boolean {
  return parseCopyGroupFilterValue(value) != null
}

export function resolveCopyGroupAccountIdsForFilter(
  accountFilter: string,
  copyGroups: readonly CopyTradingGroup[]
): string[] | null {
  const groupId = parseCopyGroupFilterValue(accountFilter)
  if (!groupId) return null
  return copyGroups.find((group) => group.id === groupId)?.accountIds ?? []
}

export function findCopyGroupByFilterValue(
  value: string | null | undefined,
  copyGroups: readonly CopyTradingGroup[]
): CopyTradingGroup | null {
  const groupId = parseCopyGroupFilterValue(value)
  if (!groupId) return null
  return copyGroups.find((group) => group.id === groupId) ?? null
}

export function findCopyGroupById(
  groupId: string | null | undefined,
  copyGroups: readonly CopyTradingGroup[]
): CopyTradingGroup | null {
  if (!groupId) return null
  return copyGroups.find((group) => group.id === groupId) ?? null
}

export function isValidAccountFilterValue(
  accountFilter: string,
  accountOptions: readonly { value: string }[],
  copyGroups: readonly CopyTradingGroup[]
): boolean {
  if (!accountFilter || accountFilter === "all") return true
  if (isCopyGroupFilterValue(accountFilter)) {
    const groupId = parseCopyGroupFilterValue(accountFilter)
    return Boolean(groupId && copyGroups.some((group) => group.id === groupId))
  }
  return accountOptions.some((option) => option.value === accountFilter)
}
