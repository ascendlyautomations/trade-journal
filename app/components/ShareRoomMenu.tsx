"use client"

import DropdownMenu from "@/app/components/ui/DropdownMenu"
import { profilePath } from "@/lib/profileRoutes"
import { pendingRoomShareFromRoom } from "@/lib/roomSharePost"
import { useRouter } from "next/navigation"

type ShareRoomMenuRoom = {
  id: string
  name?: string | null
  description?: string | null
  image_url?: string | null
  slug?: string | null
}

type ShareRoomMenuProps = {
  room: ShareRoomMenuRoom
  inviteLink: string
  user: { id: string; username?: string | null } | null
  onCopyLink?: () => void
  triggerClassName?: string
  iconClassName?: string
  menuAlign?: "left" | "right"
}

function ShareRoomIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      className={className ?? "h-4 w-4 text-blue-300"}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      aria-hidden
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
      />
    </svg>
  )
}

export default function ShareRoomMenu({
  room,
  inviteLink,
  user,
  onCopyLink,
  triggerClassName = "flex items-center justify-center rounded-md p-2 text-gray-300 hover:bg-white/10 hover:text-white",
  iconClassName,
  menuAlign = "right",
}: ShareRoomMenuProps) {
  const router = useRouter()

  return (
    <DropdownMenu
      align={menuAlign}
      stopPropagation
      trigger={
        <span
          className={triggerClassName}
          aria-label="Share room"
          title="Share room"
        >
          <ShareRoomIcon className={iconClassName} />
        </span>
      }
      items={[
        {
          id: "copy-link",
          label: "Copy Link",
          onSelect: () => {
            if (!inviteLink) return
            void navigator.clipboard.writeText(inviteLink)
            onCopyLink?.()
          },
        },
        {
          id: "create-feed-post",
          label: "Create Feed Post",
          disabled: !user?.id,
          onSelect: () => {
            if (!user?.id) return
            const draft = pendingRoomShareFromRoom(room)
            try {
              sessionStorage.setItem(
                "pendingRoomShareDraft",
                JSON.stringify(draft)
              )
            } catch {
              // sessionStorage may be unavailable; profile page can refetch by id
            }
            const params = new URLSearchParams({
              tab: "posts",
              createPost: "1",
              shareRoom: draft.roomId,
            })
            router.push(`${profilePath(user)}?${params.toString()}`)
          },
        },
      ]}
    />
  )
}
