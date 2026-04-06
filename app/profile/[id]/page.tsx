"use client"

import Navbar from "../../components/Navbar"
import { useEffect, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { useParams, useRouter } from "next/navigation"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
} from "recharts"

function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

export default function ProfilePage() {
  const params = useParams()
  const router = useRouter()
  const rawId = params.id
  const profileId =
    typeof rawId === "string" ? rawId : Array.isArray(rawId) ? rawId[0] : undefined

  const [profile, setProfile] = useState<any>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [followersCount, setFollowersCount] = useState(0)
  const [followingCount, setFollowingCount] = useState(0)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [isFollowing, setIsFollowing] = useState(false)
  const [followBusy, setFollowBusy] = useState(false)
  const [messageBusy, setMessageBusy] = useState(false)
  const [showFollowers, setShowFollowers] = useState(false)
  const [showFollowing, setShowFollowing] = useState(false)
  const [followersModalUsers, setFollowersModalUsers] = useState<any[]>([])
  const [followingModalUsers, setFollowingModalUsers] = useState<any[]>([])
  const [posts, setPosts] = useState<any[]>([])
  const [activeTab, setActiveTab] = useState<"public" | "stats">("public")
  const [selectedPost, setSelectedPost] = useState<any>(null)

  const fetchTrades = async (forProfileId: string) => {
    console.log("ProfileId being used:", forProfileId)

    const { data, error } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", forProfileId)
      .order("created_at", { ascending: false })

    console.log("Trades returned:", data)

    if (error) {
      console.error("Trade fetch error FULL:", JSON.stringify(error, null, 2))
      return
    }

    setTrades(data || [])
  }

  useEffect(() => {
    if (!profileId) {
      setProfile(null)
      setTrades([])
      setLoading(false)
      return
    }

    console.log("ProfileId from URL:", profileId)

    setProfile(null)
    setTrades([])
    setPosts([])
    setSelectedPost(null)
    setLoading(true)

    fetchProfile(profileId)
  }, [profileId])

  useEffect(() => {
    console.log("Trades:", trades)
  }, [trades])

  async function fetchPosts(forProfileId: string) {
    const { data } = await supabase
      .from("posts")
      .select("*")
      .eq("user_id", forProfileId)
      .order("created_at", { ascending: false })

    const list = data || []
    if (!list.length) {
      setPosts([])
      return
    }

    const ids = list.map((p) => p.id)

    const [
      { data: likesRows },
      { data: commentsRows },
      { count: likesExactCount },
    ] = await Promise.all([
      supabase.from("likes").select("post_id, user_id").in("post_id", ids),
      supabase
        .from("comments")
        .select("*, profiles(username)")
        .in("post_id", ids)
        .order("created_at", { ascending: true }),
      supabase
        .from("likes")
        .select("*", { count: "exact", head: true })
        .in("post_id", ids),
    ])
    void likesExactCount

    const likesCountByPost: Record<string, number> = {}
    for (const id of ids) {
      likesCountByPost[String(id)] = 0
    }
    for (const row of likesRows || []) {
      const pid = String(row.post_id)
      likesCountByPost[pid] = (likesCountByPost[pid] || 0) + 1
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) {
      commentsMap[String(id)] = []
    }
    for (const c of commentsRows || []) {
      const pid = String(c.post_id)
      if (!commentsMap[pid]) commentsMap[pid] = []
      commentsMap[pid].push(c)
    }

    const enriched = list.map((p) => {
      const key = String(p.id)
      return {
        ...p,
        likesCount: likesCountByPost[key] ?? 0,
        comments: commentsMap[key] ?? [],
      }
    })
    setPosts(enriched)
  }

  useEffect(() => {
    if (profile?.id) {
      fetchPosts(profile.id)
    } else {
      setPosts([])
    }
  }, [profile?.id])

  useEffect(() => {
    if (selectedPost) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
  }, [selectedPost])

  async function fetchProfile(forProfileId: string) {
    const { data: sessionData } = await supabase.auth.getSession()
    const uid = sessionData?.session?.user?.id ?? null
    setCurrentUserId(uid)

    const { data: prof, error } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", forProfileId)
      .single()

    if (!prof || error) {
      setProfile(null)
      setTrades([])
      setPosts([])
      setFollowersCount(0)
      setFollowingCount(0)
      setIsFollowing(false)
      setLoading(false)
      return
    }

    let following = false
    if (uid && uid !== prof.id) {
      const { data: followRow } = await supabase
        .from("followers")
        .select("*")
        .eq("follower_id", uid)
        .eq("following_id", prof.id)
        .maybeSingle()

      following = !!followRow
    }

    setProfile(prof)
    setIsFollowing(following)

    const { count: followersN } = await supabase
      .from("followers")
      .select("*", { count: "exact", head: true })
      .eq("following_id", prof.id)

    const { count: followingN } = await supabase
      .from("followers")
      .select("*", { count: "exact", head: true })
      .eq("follower_id", prof.id)

    setFollowersCount(followersN ?? 0)
    setFollowingCount(followingN ?? 0)

    const isPrivateProfile = prof.is_private === true
    const canLoadTrades =
      !isPrivateProfile || uid === forProfileId || following

    if (canLoadTrades) {
      await fetchTrades(forProfileId)
    } else {
      setTrades([])
    }

    setLoading(false)
  }

  async function handleFollowToggle() {
    if (!currentUserId || !profile || currentUserId === profile.id || followBusy)
      return

    setFollowBusy(true)

    if (isFollowing) {
      await supabase
        .from("followers")
        .delete()
        .eq("follower_id", currentUserId)
        .eq("following_id", profile.id)

      setIsFollowing(false)
      if (profile.is_private === true) {
        setTrades([])
      }
    } else {
      await supabase.from("followers").insert({
        follower_id: currentUserId,
        following_id: profile.id,
      })

      setIsFollowing(true)
      if (profile.is_private === true && profileId) {
        await fetchTrades(profileId)
      }
    }

    const { count: followersN } = await supabase
      .from("followers")
      .select("*", { count: "exact", head: true })
      .eq("following_id", profile.id)

    setFollowersCount(followersN ?? 0)

    setFollowBusy(false)
  }

  async function findExistingDmConversationId(
    me: string,
    them: string
  ): Promise<string | null> {
    const { data: mine } = await supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", me)

    const ids = [...new Set(mine?.map((r) => r.conversation_id) ?? [])]
    if (ids.length === 0) return null

    const { data: rows } = await supabase
      .from("conversation_participants")
      .select("conversation_id, user_id")
      .in("conversation_id", ids)

    const byConvo = new Map<string, Set<string>>()
    for (const row of rows ?? []) {
      if (!byConvo.has(row.conversation_id)) {
        byConvo.set(row.conversation_id, new Set())
      }
      byConvo.get(row.conversation_id)!.add(row.user_id)
    }

    for (const [cid, users] of byConvo) {
      if (users.size === 2 && users.has(me) && users.has(them)) return cid
    }

    return null
  }

  async function handleMessage() {
    if (!currentUserId || !profile || currentUserId === profile.id) return

    setMessageBusy(true)
    try {
      const existingId = await findExistingDmConversationId(
        currentUserId,
        profile.id
      )

      if (existingId) {
        router.push(`/messages/${existingId}`)
        return
      }

      const { data: convo, error: convErr } = await supabase
        .from("conversations")
        .insert({})
        .select("id")
        .single()

      if (convErr || !convo?.id) {
        console.error(convErr)
        return
      }

      const { error: partErr } = await supabase
        .from("conversation_participants")
        .insert([
          { conversation_id: convo.id, user_id: currentUserId },
          { conversation_id: convo.id, user_id: profile.id },
        ])

      if (partErr) {
        console.error(partErr)
        return
      }

      router.push(`/messages/${convo.id}`)
    } finally {
      setMessageBusy(false)
    }
  }

  function closeFollowModals() {
    setShowFollowers(false)
    setShowFollowing(false)
  }

  async function openFollowersModal() {
    if (!profile) return
    setShowFollowing(false)
    setShowFollowers(true)

    const { data: rows } = await supabase
      .from("followers")
      .select("follower_id")
      .eq("following_id", profile.id)

    const ids = [...new Set(rows?.map((r) => r.follower_id).filter(Boolean) ?? [])]
    if (ids.length === 0) {
      setFollowersModalUsers([])
      return
    }

    const { data: profs } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, name")
      .in("id", ids)

    setFollowersModalUsers(profs ?? [])
  }

  async function openFollowingModal() {
    if (!profile) return
    setShowFollowers(false)
    setShowFollowing(true)

    const { data: rows } = await supabase
      .from("followers")
      .select("following_id")
      .eq("follower_id", profile.id)

    const ids = [...new Set(rows?.map((r) => r.following_id).filter(Boolean) ?? [])]
    if (ids.length === 0) {
      setFollowingModalUsers([])
      return
    }

    const { data: profs } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, name")
      .in("id", ids)

    setFollowingModalUsers(profs ?? [])
  }

  const canViewTrades =
    !!profile &&
    (profile.is_private !== true ||
      currentUserId === profile.id ||
      isFollowing)

  const totalTrades = canViewTrades ? trades.length : 0
  const wins = canViewTrades ? trades.filter((t) => t.pnl > 0).length : 0
  const totalPnL = canViewTrades
    ? trades.reduce((sum, t) => sum + (t.pnl || 0), 0)
    : 0
  const winRate =
    canViewTrades && totalTrades ? (wins / totalTrades) * 100 : 0
  const avgRR =
    canViewTrades && totalTrades
      ? trades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
        totalTrades
      : 0

  const biggestWin = trades.length
    ? Math.max(...trades.map((t) => t.pnl || 0))
    : 0

  const biggestLoss = trades.length
    ? Math.min(...trades.map((t) => t.pnl || 0))
    : 0

  const longTrades = trades.filter((t) => t.direction === "Long").length
  const shortTrades = trades.filter((t) => t.direction === "Short").length

  const equityData = trades
    .slice()
    .reverse()
    .reduce(
      (acc: { index: number; equity: number }[], trade, i) => {
        const prev = acc[i - 1]?.equity || 0
        acc.push({
          index: i,
          equity: prev + (trade.pnl || 0),
        })
        return acc
      },
      [] as { index: number; equity: number }[]
    )

  function formatCurrency(value: number) {
    return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString()}`
  }

  function getTradingDuration(startDate: any) {
    if (!startDate) return "N/A"

    const start = new Date(startDate)
    const now = new Date()

    let years = now.getFullYear() - start.getFullYear()
    let months = now.getMonth() - start.getMonth()

    if (months < 0) {
      years--
      months += 12
    }

    if (years <= 0) return `${months} months`
    return `${years}y ${months}m`
  }

  if (!profileId) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-red-400">
          Invalid profile
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-400">
          Loading profile...
        </div>
      </>
    )
  }

  if (!profile) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-red-400">
          User not found
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="mx-auto max-w-7xl space-y-4 p-5">
        <div className="mx-auto max-w-5xl">

          <div className="mb-10 flex items-start gap-4">
            <img
              src={profile.avatar_url || "/default-avatar.png"}
              alt=""
              onError={(e) => {
                e.currentTarget.src = "/default-avatar.png"
              }}
              className="w-16 h-16 shrink-0 rounded-full object-cover"
            />

            <div className="min-w-0 flex-1">
              <div className="flex w-full flex-col">
                <div className="flex flex-wrap items-center gap-3">
                  <h1 className="text-xl font-semibold leading-tight">
                    {profile.name || "User"}
                  </h1>

                  {currentUserId && currentUserId !== profile.id && (
                    <div className="ml-2 flex gap-2">
                      <button
                        type="button"
                        onClick={handleFollowToggle}
                        disabled={followBusy}
                        className={`rounded px-3 py-1 text-sm font-semibold text-gray-100 disabled:opacity-50 ${
                          isFollowing ? "bg-red-500 hover:bg-red-600" : "bg-blue-500 hover:bg-blue-600"
                        }`}
                      >
                        {isFollowing ? "Unfollow" : "Follow"}
                      </button>

                      <button
                        type="button"
                        onClick={handleMessage}
                        disabled={messageBusy}
                        className="rounded border border-white/10 bg-white/10 px-3 py-1 text-sm text-gray-100 hover:bg-white/15 disabled:opacity-50"
                      >
                        Message
                      </button>
                    </div>
                  )}
                </div>

                <p className="text-sm text-gray-400">@{profile.username}</p>

                <div className="mt-1 flex gap-4 text-sm text-gray-400">
                  <span
                    role="button"
                    tabIndex={0}
                    onClick={openFollowersModal}
                    onKeyDown={(e) =>
                      e.key === "Enter" && openFollowersModal()
                    }
                    className="cursor-pointer hover:text-white"
                  >
                    {followersCount} Followers
                  </span>
                  <span
                    role="button"
                    tabIndex={0}
                    onClick={openFollowingModal}
                    onKeyDown={(e) =>
                      e.key === "Enter" && openFollowingModal()
                    }
                    className="cursor-pointer hover:text-white"
                  >
                    {followingCount} Following
                  </span>
                </div>
              </div>

              {profile.bio ? (
                <p className="mt-2 max-w-md text-sm text-gray-400">
                  {profile.bio}
                </p>
              ) : (
                <p className="mt-2 max-w-md text-sm italic text-gray-400">
                  No bio yet
                </p>
              )}

              <div className="mt-2 space-y-1">
                <div className="flex items-center gap-2">
                  <span className="text-gray-400 text-sm">Strategy:</span>
                  <span className="text-emerald-400 text-sm font-semibold">
                    {profile?.trading_model || "N/A"}
                  </span>
                </div>

                <div className="flex items-center gap-2">
                  <span className="text-gray-400 text-sm">Experience:</span>
                  <span className="text-blue-400 text-sm font-semibold">
                    {getTradingDuration(profile?.started_trading)}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div className="mt-6 flex justify-center gap-4">
            {(["public", "stats"] as const).map((tab) => (
              <button
                key={tab}
                type="button"
                onClick={() => setActiveTab(tab)}
                className={`px-4 py-2 rounded ${
                  activeTab === tab
                    ? "bg-blue-500 text-white"
                    : "bg-white/10 hover:bg-white/20"
                }`}
              >
                {tab === "public"
                  ? "Public Trades"
                  : tab.charAt(0).toUpperCase() + tab.slice(1)}
              </button>
            ))}
          </div>

          <div className="mx-auto mt-2 max-w-3xl space-y-6 px-0 sm:px-2">
            {activeTab === "public" && (
              <div className="space-y-4">
                <h2 className="text-xl font-semibold text-white">
                  Public Trades
                </h2>
                {posts.length === 0 ? (
                  <p className="text-sm text-gray-400">No public trades yet</p>
                ) : (
                  <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                    {posts.map((post) => {
                      const imageSrc = postImageSrc(post.image_url)
                      const pnl = Number(post.pnl)
                      const pnlPositive = !Number.isNaN(pnl) && pnl >= 0

                      return (
                        <div
                          key={post.id}
                          role="button"
                          tabIndex={0}
                          onClick={() => setSelectedPost(post)}
                          onKeyDown={(e) => {
                            if (e.key === "Enter" || e.key === " ") {
                              e.preventDefault()
                              setSelectedPost(post)
                            }
                          }}
                          className="cursor-pointer overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07]"
                        >
                          {imageSrc ? (
                            <div className="w-full bg-black/30">
                              <img
                                src={imageSrc}
                                alt=""
                                className="max-h-[240px] w-full object-cover md:max-h-[280px]"
                              />
                            </div>
                          ) : null}
                          <div className="flex items-center justify-between gap-4 p-4 text-sm">
                            <span
                              className={`font-semibold tabular-nums ${
                                pnlPositive
                                  ? "text-emerald-400"
                                  : "text-red-400"
                              }`}
                            >
                              {Number.isNaN(pnl)
                                ? "—"
                                : `${pnlPositive ? "+" : ""}$${pnl}`}
                            </span>
                            <span className="shrink-0 text-gray-300 tabular-nums">
                              RR{" "}
                              {post.rr != null && post.rr !== ""
                                ? post.rr
                                : "—"}
                            </span>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
            )}

            {activeTab === "stats" && (
              <div className="space-y-6">
                {!canViewTrades ? (
                  <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
                    <p className="text-lg text-gray-100">Private Profile</p>
                    <p className="mt-2 text-sm text-gray-400">
                      Follow this user to see their trades and stats.
                    </p>
                  </div>
                ) : (
                  <>
                    <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
                      <Stat title="Trades" value={totalTrades} />

                      <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />

                      <Stat
                        title="Total P&L"
                        value={formatCurrency(totalPnL)}
                        positive={totalPnL >= 0}
                      />

                      <Stat title="Avg RR" value={avgRR.toFixed(2)} />
                    </div>

                    <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Biggest Win</p>
                        <p className="font-semibold text-green-400">
                          ${biggestWin.toFixed(2)}
                        </p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Biggest Loss</p>
                        <p className="font-semibold text-red-400">
                          ${biggestLoss.toFixed(2)}
                        </p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Long Trades</p>
                        <p className="font-semibold">{longTrades}</p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Short Trades</p>
                        <p className="font-semibold">{shortTrades}</p>
                      </div>
                    </div>

                    <div className="rounded-xl border border-white/10 bg-white/5 p-6">
                      <h2 className="mb-4 text-lg font-semibold">Equity Curve</h2>

                      <div className="h-64">
                        <ResponsiveContainer width="100%" height="100%">
                          <LineChart data={equityData}>
                            <XAxis dataKey="index" hide />
                            <YAxis />
                            <Tooltip />
                            <Line
                              type="monotone"
                              dataKey="equity"
                              stroke="#10b981"
                              strokeWidth={2}
                              dot={false}
                            />
                          </LineChart>
                        </ResponsiveContainer>
                      </div>
                    </div>
                  </>
                )}
              </div>
            )}
          </div>

        </div>
        </div>

      </div>

      {selectedPost && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
          onClick={() => setSelectedPost(null)}
        >
          <div
            className="relative w-full max-w-2xl rounded-xl bg-[#0f172a] p-4"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => setSelectedPost(null)}
              className="absolute right-2 top-2 text-xl text-white"
              aria-label="Close"
            >
              ✕
            </button>

            {selectedPost.image_url ? (
              <img
                src={
                  String(selectedPost.image_url).startsWith("http")
                    ? selectedPost.image_url
                    : `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${selectedPost.image_url}`
                }
                alt=""
                className="w-full max-h-[400px] rounded-lg object-cover"
              />
            ) : null}

            <div className="mt-3 space-y-2 text-sm">
              <div className="flex justify-between">
                <span
                  className={
                    Number(selectedPost.pnl) >= 0
                      ? "text-green-400"
                      : "text-red-400"
                  }
                >
                  ${selectedPost.pnl}
                </span>
                <span>RR {selectedPost.rr}</span>
              </div>

              <div className="flex justify-between text-gray-300">
                <span>Points: {selectedPost.points || "-"}</span>
                <span>Account: {selectedPost.account_type || "-"}</span>
              </div>
            </div>

            <div className="mt-3 text-sm text-gray-300">
              ❤️ {selectedPost.likesCount || 0} likes
            </div>

            <div className="mt-2 max-h-40 space-y-1 overflow-y-auto">
              {selectedPost.comments?.map((c: any) => (
                <div key={c.id} className="text-sm">
                  <span className="font-semibold">
                    {c.profiles?.username || "User"}
                  </span>{" "}
                  {c.content}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {showFollowers && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm"
          onClick={closeFollowModals}
        >
          <div
            className="max-h-[400px] w-80 overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-4 text-lg font-semibold text-gray-100">Followers</h2>

            {followersModalUsers.length === 0 ? (
              <p className="text-sm text-gray-400">No followers yet.</p>
            ) : (
              <div className="space-y-1">
                {followersModalUsers.map((u) => (
                  <div
                    key={u.id}
                    className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
                    onClick={() => {
                      closeFollowModals()
                      router.push(`/profile/${u.id}`)
                    }}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      onError={(e) => {
                        e.currentTarget.src = "/default-avatar.png"
                      }}
                      className="h-8 w-8 rounded-full object-cover"
                    />
                    <span className="text-white">{u.username}</span>
                  </div>
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={closeFollowModals}
              className="mt-4 w-full rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20"
            >
              Close
            </button>
          </div>
        </div>
      )}

      {showFollowing && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm"
          onClick={closeFollowModals}
        >
          <div
            className="max-h-[400px] w-80 overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-4 text-lg font-semibold text-gray-100">Following</h2>

            {followingModalUsers.length === 0 ? (
              <p className="text-sm text-gray-400">Not following anyone yet.</p>
            ) : (
              <div className="space-y-1">
                {followingModalUsers.map((u) => (
                  <div
                    key={u.id}
                    className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
                    onClick={() => {
                      closeFollowModals()
                      router.push(`/profile/${u.id}`)
                    }}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      onError={(e) => {
                        e.currentTarget.src = "/default-avatar.png"
                      }}
                      className="h-8 w-8 rounded-full object-cover"
                    />
                    <span className="text-white">{u.username}</span>
                  </div>
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={closeFollowModals}
              className="mt-4 w-full rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </>
  )
}

function Stat({ title, value, positive }: any) {
  let color = "text-gray-100"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
    </div>
  )
}
