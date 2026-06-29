"use client"

import Link from "next/link"
import type { ComponentProps, ReactNode } from "react"
import { profilePath } from "@/lib/profileRoutes"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar"

type ProfileLinkProps = Omit<ComponentProps<typeof Link>, "href"> & {
  userId: string
  username?: string | null
  stopPropagation?: boolean
}

export function ProfileLink({
  userId,
  username,
  stopPropagation = false,
  onClick,
  className,
  children,
  ...rest
}: ProfileLinkProps) {
  if (!userId) {
    return <span className={className}>{children}</span>
  }

  return (
    <Link
      href={profilePath({ id: userId, username })}
      className={className}
      onClick={(e) => {
        if (stopPropagation) e.stopPropagation()
        onClick?.(e)
      }}
      {...rest}
    >
      {children}
    </Link>
  )
}

type ProfileAvatarLinkProps = Omit<ProfileLinkProps, "children"> & {
  src?: string | null
  alt?: string
  imgClassName?: string
  priority?: boolean
}

export function ProfileAvatarLink({
  src,
  alt = "",
  imgClassName = "h-10 w-10 rounded-full object-cover",
  priority,
  className = "inline-flex shrink-0 cursor-pointer transition hover:opacity-90",
  ...linkProps
}: ProfileAvatarLinkProps) {
  return (
    <ProfileLink {...linkProps} className={className}>
      <SafeProfileAvatar
        src={src}
        alt={alt}
        className={imgClassName}
        priority={priority}
      />
    </ProfileLink>
  )
}

type ProfileUsernameLinkProps = Omit<ProfileLinkProps, "children"> & {
  children?: ReactNode
  fallback?: string
}

export function ProfileUsernameLink({
  children,
  fallback = "User",
  username,
  className = "cursor-pointer transition hover:opacity-90",
  ...linkProps
}: ProfileUsernameLinkProps) {
  return (
    <ProfileLink {...linkProps} className={className}>
      {children ?? (username?.trim() || fallback)}
    </ProfileLink>
  )
}
