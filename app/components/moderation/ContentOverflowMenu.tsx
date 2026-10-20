"use client"

import DropdownMenu, {
  type DropdownMenuItem,
} from "@/app/components/ui/DropdownMenu"

type ContentOverflowMenuProps = {
  onReport?: () => void
  onBlockUser?: () => void
  align?: "left" | "right"
  /** Extra owner actions render before report/block when provided. */
  ownerItems?: Array<{
    id: string
    label: string
    onSelect: () => void
    variant?: "default" | "danger"
  }>
}

export default function ContentOverflowMenu({
  onReport,
  onBlockUser,
  align = "right",
  ownerItems = [],
}: ContentOverflowMenuProps) {
  const items: DropdownMenuItem[] = [
    ...ownerItems.map((item) => ({
      id: item.id,
      label: item.label,
      onSelect: item.onSelect,
      variant: item.variant,
    })),
  ]
  if (onReport) {
    items.push({ id: "report", label: "Report", onSelect: onReport })
  }
  if (onBlockUser) {
    items.push({
      id: "block",
      label: "Block user",
      onSelect: onBlockUser,
      variant: "danger" as const,
    })
  }
  if (items.length === 0) return null

  return (
    <DropdownMenu
      align={align}
      stopPropagation
      menuClassName="z-[9100]"
      trigger={
        <span className="inline-flex h-9 w-9 items-center justify-center text-lg text-gray-400 hover:text-white">
          ⋯
        </span>
      }
      items={items}
    />
  )
}
