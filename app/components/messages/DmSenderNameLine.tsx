"use client"

import {
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { resolveDmSenderDisplay } from "@/lib/deletedUserDisplay"

type DmSenderNameLineProps = {
  message: Parameters<typeof resolveDmSenderDisplay>[0]
  className?: string
}

/** Group-chat sender label — profile link disabled for deleted accounts. */
export function DmSenderNameLine({
  message,
  className = "mb-1 ml-1 inline-block text-xs text-gray-400 hover:text-gray-300",
}: DmSenderNameLineProps) {
  const sender = resolveDmSenderDisplay(message)

  if (!sender.profileLinkEnabled) {
    return (
      <span className={`${className} cursor-default hover:text-gray-400`.trim()}>
        {sender.username}
      </span>
    )
  }

  return (
    <ProfileUsernameLink
      userId={sender.userId!}
      username={sender.username}
      className={className}
    />
  )
}
