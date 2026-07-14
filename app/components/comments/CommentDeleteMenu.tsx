"use client"

import DropdownMenu, {
  type DropdownMenuItem,
} from "@/app/components/ui/DropdownMenu"

type CommentActionsMenuProps = {
  canPin?: boolean
  isPinned?: boolean
  canDelete?: boolean
  onPin?: () => void
  onUnpin?: () => void
  onDelete?: () => void
  menuClassName?: string
}

export default function CommentActionsMenu({
  canPin = false,
  isPinned = false,
  canDelete = false,
  onPin,
  onUnpin,
  onDelete,
  menuClassName,
}: CommentActionsMenuProps) {
  const items: DropdownMenuItem[] = []

  if (canPin) {
    if (isPinned) {
      items.push({
        id: "unpin",
        label: "Unpin Comment",
        onSelect: onUnpin,
      })
    } else {
      items.push({
        id: "pin",
        label: "Pin Comment",
        onSelect: onPin,
      })
    }
  }

  if (canDelete && onDelete) {
    items.push({
      id: "delete",
      label: "Delete Comment",
      variant: "danger",
      onSelect: onDelete,
    })
  }

  if (items.length === 0) return null

  return (
    <DropdownMenu
      stopPropagation
      align="right"
      menuClassName={menuClassName}
      trigger={
        <span
          className="rounded px-1.5 py-0.5 text-xs text-gray-400 opacity-100 transition-opacity hover:text-gray-200 sm:opacity-0 sm:group-hover:opacity-100"
          aria-label="Comment actions"
        >
          ⋯
        </span>
      }
      items={items}
    />
  )
}

/** @deprecated Prefer CommentActionsMenu */
export function CommentDeleteMenu({
  onDelete,
  menuClassName,
}: {
  onDelete: () => void
  menuClassName?: string
}) {
  return (
    <CommentActionsMenu
      canDelete
      onDelete={onDelete}
      menuClassName={menuClassName}
    />
  )
}
