"use client"

import DropdownMenu from "@/app/components/ui/DropdownMenu"

type CommentDeleteMenuProps = {
  onDelete: () => void
  menuClassName?: string
}

export default function CommentDeleteMenu({
  onDelete,
  menuClassName,
}: CommentDeleteMenuProps) {
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
      items={[
        {
          id: "delete",
          label: "Delete",
          variant: "danger",
          onSelect: onDelete,
        },
      ]}
    />
  )
}
