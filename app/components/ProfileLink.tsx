"use client"

import Link from "next/link"
import type { ComponentProps, ReactNode } from "react"
import { profilePath } from "@/lib/profileRoutes"

const DEFAULT_AVATAR = "/default-avatar.png"

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
}

export function ProfileAvatarLink({
  src,
  alt = "",
  imgClassName = "rounded-full object-cover",
  className = "inline-flex shrink-0 cursor-pointer transition hover:opacity-90",
  ...linkProps
}: ProfileAvatarLinkProps) {
  return (
    <ProfileLink {...linkProps} className={className}>
      <img
        src={src?.trim() || DEFAULT_AVATAR}
        alt={alt}
        loading="lazy"
        decoding="async"
        className={imgClassName}
        onError={(e) => {
          e.currentTarget.src = DEFAULT_AVATAR
        }}
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
