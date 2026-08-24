"use client"

import Link from "next/link"
import type { ComponentProps, ReactNode } from "react"
import { profilePath } from "@/lib/profileRoutes"
import { writeProfileHeaderPreview } from "@/lib/profilePreviewCache"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar"

export type ProfileLinkPreviewSeed = {
  name?: string | null
  avatar_url?: string | null
  is_private?: boolean | null
}

type ProfileLinkProps = Omit<ComponentProps<typeof Link>, "href"> & {
  userId: string
  username?: string | null
  stopPropagation?: boolean
  preview?: ProfileLinkPreviewSeed
}

function seedProfilePreview(
  userId: string,
  username: string | null | undefined,
  preview?: ProfileLinkPreviewSeed
) {
  writeProfileHeaderPreview(username?.trim() || userId, {
    id: userId,
    username,
    name: preview?.name,
    avatar_url: preview?.avatar_url,
    is_private: preview?.is_private,
  })
}

export function ProfileLink({
  userId,
  username,
  stopPropagation = false,
  preview,
  onClick,
  onMouseEnter,
  onFocus,
  onTouchStart,
  className,
  children,
  prefetch = false,
  ...rest
}: ProfileLinkProps) {
  if (!userId) {
    return <span className={className}>{children}</span>
  }

  const seed = () => seedProfilePreview(userId, username, preview)

  return (
    <Link
      href={profilePath({ id: userId, username })}
      prefetch={prefetch}
      className={className}
      onMouseEnter={(e) => {
        seed()
        onMouseEnter?.(e)
      }}
      onFocus={(e) => {
        seed()
        onFocus?.(e)
      }}
      onTouchStart={(e) => {
        seed()
        onTouchStart?.(e)
      }}
      onClick={(e) => {
        seed()
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
  preview,
  username,
  userId,
  ...linkProps
}: ProfileAvatarLinkProps) {
  const mergedPreview: ProfileLinkPreviewSeed = {
    ...preview,
    avatar_url: preview?.avatar_url ?? src,
    name: preview?.name ?? (alt || undefined),
  }

  return (
    <ProfileLink
      {...linkProps}
      userId={userId}
      username={username}
      preview={mergedPreview}
      className={className}
    >
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
  preview,
  userId,
  ...linkProps
}: ProfileUsernameLinkProps) {
  const mergedPreview: ProfileLinkPreviewSeed = {
    ...preview,
    name: preview?.name ?? (typeof children === "string" ? children : undefined),
  }

  return (
    <ProfileLink
      {...linkProps}
      userId={userId}
      username={username}
      preview={mergedPreview}
      className={className}
    >
      {children ?? (username?.trim() || fallback)}
    </ProfileLink>
  )
}
