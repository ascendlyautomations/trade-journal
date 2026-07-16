"use client"

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { createPortal } from "react-dom"
import Link from "next/link"
import EmptyState from "@/app/components/ui/EmptyState"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import Skeleton from "@/app/components/ui/Skeleton"
import { useModalScrollLock } from "@/app/components/ui/modalLayout"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { ProfileLink } from "@/app/components/ProfileLink"
import { supabase } from "@/lib/supabaseClient"
import {
  FOLLOW_LIST_PAGE_SIZE,
  fetchFollowListPage,
  getFollowListCache,
  setFollowListCache,
  type FollowListKind,
  type FollowListUser,
} from "@/lib/followListPage"

type FollowListModalProps = {
  open: boolean
  onClose: () => void
  profileId: string
  kind: FollowListKind
  isOwnProfile: boolean
}

function FollowListEmpty({
  kind,
  isOwnProfile,
}: {
  kind: FollowListKind
  isOwnProfile: boolean
}) {
  if (kind === "followers") {
    if (isOwnProfile) {
      return (
        <EmptyState
          title="No Followers Yet"
          description="Post consistently and engage with other traders to grow your audience."
          className="border-0 bg-transparent py-6"
        />
      )
    }
    return <p className="text-sm text-gray-400">No followers yet.</p>
  }

  if (isOwnProfile) {
    return (
      <EmptyState
        title="Not Following Anyone"
        description="Follow traders to customize your feed."
        action={
          <Link
            href="/explore"
            className="text-sm font-medium text-blue-300 hover:text-blue-200"
          >
            Explore Traders →
          </Link>
        }
        className="border-0 bg-transparent py-6"
      />
    )
  }

  return <p className="text-sm text-gray-400">Not following anyone yet.</p>
}

function UserRowsSkeleton() {
  return (
    <div className="space-y-2" aria-hidden>
      {Array.from({ length: 5 }, (_, i) => (
        <div key={i} className="flex items-center gap-3 rounded-lg p-2">
          <Skeleton className="h-8 w-8 rounded-full" />
          <Skeleton className="h-4 w-28" />
        </div>
      ))}
    </div>
  )
}

function appendUniqueUsers(
  prev: FollowListUser[],
  next: FollowListUser[]
): FollowListUser[] {
  if (next.length === 0) return prev
  const seen = new Set(prev.map((u) => u.id))
  const merged = [...prev]
  for (const user of next) {
    if (seen.has(user.id)) continue
    seen.add(user.id)
    merged.push(user)
  }
  return merged
}

export default function FollowListModal({
  open,
  onClose,
  profileId,
  kind,
  isOwnProfile,
}: FollowListModalProps) {
  const [mounted, setMounted] = useState(false)
  const [users, setUsers] = useState<FollowListUser[]>([])
  const [nextOffset, setNextOffset] = useState(0)
  const [hasMore, setHasMore] = useState(true)
  const [initialLoading, setInitialLoading] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)

  const scrollRef = useRef<HTMLDivElement>(null)
  const sentinelRef = useRef<HTMLDivElement>(null)
  const fetchInFlightRef = useRef(false)
  const nextOffsetRef = useRef(0)
  const hasMoreRef = useRef(true)

  useModalScrollLock(open)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  const persistCache = useCallback(
    (nextUsers: FollowListUser[], offset: number, more: boolean) => {
      setFollowListCache(profileId, kind, {
        users: nextUsers,
        nextOffset: offset,
        hasMore: more,
      })
    },
    [profileId, kind]
  )

  const loadPage = useCallback(
    async (offset: number, mode: "initial" | "more") => {
      if (fetchInFlightRef.current) return
      if (mode === "more" && !hasMoreRef.current) return

      fetchInFlightRef.current = true
      if (mode === "initial") setInitialLoading(true)
      else setLoadingMore(true)

      try {
        const page = await fetchFollowListPage(
          supabase,
          profileId,
          kind,
          offset,
          FOLLOW_LIST_PAGE_SIZE
        )

        setUsers((prev) => {
          const merged =
            mode === "initial"
              ? page.users
              : appendUniqueUsers(prev, page.users)
          nextOffsetRef.current = page.nextOffset
          hasMoreRef.current = page.hasMore
          setNextOffset(page.nextOffset)
          setHasMore(page.hasMore)
          persistCache(merged, page.nextOffset, page.hasMore)
          return merged
        })
      } catch (err) {
        console.error(`[FollowListModal] ${kind} page failed`, err)
        if (mode === "initial") {
          setUsers([])
          setNextOffset(0)
          setHasMore(false)
          nextOffsetRef.current = 0
          hasMoreRef.current = false
        }
      } finally {
        fetchInFlightRef.current = false
        setInitialLoading(false)
        setLoadingMore(false)
      }
    },
    [kind, persistCache, profileId]
  )

  useEffect(() => {
    if (!open || !profileId) return

    const cached = getFollowListCache(profileId, kind)
    if (cached) {
      setUsers(cached.users)
      setNextOffset(cached.nextOffset)
      setHasMore(cached.hasMore)
      nextOffsetRef.current = cached.nextOffset
      hasMoreRef.current = cached.hasMore
      setInitialLoading(false)
      setLoadingMore(false)
      return
    }

    setUsers([])
    setNextOffset(0)
    setHasMore(true)
    nextOffsetRef.current = 0
    hasMoreRef.current = true
    void loadPage(0, "initial")
  }, [open, profileId, kind, loadPage])

  useEffect(() => {
    if (!open || initialLoading || !hasMore) return
    const root = scrollRef.current
    const sentinel = sentinelRef.current
    if (!root || !sentinel) return

    const observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0]
        if (!entry?.isIntersecting) return
        if (fetchInFlightRef.current || !hasMoreRef.current) return
        void loadPage(nextOffsetRef.current, "more")
      },
      {
        root,
        // Prefetch when the sentinel is within ~1–2 rows of the viewport (~80%).
        rootMargin: "120px 0px",
        threshold: 0,
      }
    )

    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [open, initialLoading, hasMore, users.length, loadPage])

  if (!open || !mounted) return null

  const title = kind === "followers" ? "Followers" : "Following"
  let body: ReactNode

  if (initialLoading) {
    body = <UserRowsSkeleton />
  } else if (users.length === 0) {
    body = <FollowListEmpty kind={kind} isOwnProfile={isOwnProfile} />
  } else {
    body = (
      <>
        <div className="space-y-1">
          {users.map((u) => (
            <ProfileLink
              key={u.id}
              userId={u.id}
              username={u.username}
              onClick={onClose}
              className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
            >
              <ProfileAvatarImg src={u.avatar_url} className="h-8 w-8" />
              <span className="text-white">{u.username}</span>
            </ProfileLink>
          ))}
        </div>
        <div ref={sentinelRef} className="h-1 w-full" aria-hidden />
        {loadingMore ? (
          <div className="flex items-center justify-center gap-2 py-3 text-xs text-gray-400">
            <span
              className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-gray-400 border-t-transparent"
              aria-hidden
            />
            Loading more…
          </div>
        ) : null}
      </>
    )
  }

  return createPortal(
    <div
      className="fixed inset-0 z-[10050] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="follow-list-modal-title"
        className="flex max-h-[min(80dvh,28rem)] w-full max-w-xs flex-col overflow-hidden rounded-xl border border-white/15 bg-[#0f172a] text-gray-100 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="relative shrink-0 border-b border-white/10 px-4 py-3 pr-14">
          <h2
            id="follow-list-modal-title"
            className="text-lg font-semibold text-white"
          >
            {title}
          </h2>
          <ModalCloseButton
            onClick={onClose}
            className="absolute right-3 top-2.5 z-10"
          />
        </div>
        <div
          ref={scrollRef}
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-3"
        >
          {body}
        </div>
      </div>
    </div>,
    document.body
  )
}
