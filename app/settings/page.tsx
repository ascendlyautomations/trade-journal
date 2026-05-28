"use client"

import Navbar from "../components/Navbar"
import AffiliateApplyModal from "../components/AffiliateApplyModal"
import { useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { getMembershipStatus } from "@/lib/getMembershipStatus"
import { isProActive } from "../../lib/subscription"
import { isProfilesUsernameConflict } from "@/lib/profileUsername"
import type { User } from "@supabase/supabase-js"
import AffiliatePayoutSetupCard from "@/app/components/AffiliatePayoutSetupCard"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { fetchLatestAffiliateApplication, type AffiliateApplicationRow } from "@/lib/affiliateApplication"
import {
  AFFILIATE_CONNECT_SELECT,
  parseAffiliateConnectRow,
  type AffiliateConnectRow,
} from "@/lib/affiliateStripeConnect"
import { createUserRoom } from "@/lib/createUserRoom"

type TabId = "profile" | "affiliate" | "account" | "subscription"

function sliceDateInput(raw: unknown): string {
  if (raw == null || raw === "") return ""
  const s = String(raw)
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10)
  const d = new Date(s)
  if (Number.isNaN(d.getTime())) return ""
  return d.toISOString().slice(0, 10)
}

function subscriptionStatusClass(statusRaw: unknown): string {
  const s = String(statusRaw ?? "")
    .toLowerCase()
    .trim()
  if (s === "active") return "text-emerald-400"
  if (s === "trialing") return "text-amber-400"
  if (s === "canceled" || s === "cancelled") return "text-red-400"
  if (s === "inactive") return "text-gray-400"
  return "text-gray-300"
}

function formatStripeCustomerId(id: unknown): string {
  if (id == null || id === "") return "—"
  const s = String(id)
  return s.length > 10 ? `${s.slice(0, 10)}...` : s
}

const TABS: {
  id: TabId
  label: string
  description: string
}[] = [
  {
    id: "account",
    label: "Account",
    description: "Login, security, and privacy",
  },
  {
    id: "subscription",
    label: "Subscription",
    description: "Plan, billing, and Pro access",
  },
  {
    id: "profile",
    label: "Profile",
    description: "Public profile and trading style",
  },
  {
    id: "affiliate",
    label: "Affiliate",
    description: "Referrals, links, and earnings",
  },
]

export default function SettingsPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [activeTab, setActiveTab] = useState<TabId>("account")

  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)
  const [savingProfile, setSavingProfile] = useState(false)
  const [savingDrawdownLimit, setSavingDrawdownLimit] = useState(false)
  const [savingAccountPrivacy, setSavingAccountPrivacy] = useState(false)
  const [savingPassword, setSavingPassword] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [confirmText, setConfirmText] = useState("")
  const [manageLoading, setManageLoading] = useState(false)
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [popupMessage, setPopupMessage] = useState("")
  const [popupType, setPopupType] = useState<"success" | "error">("success")
  const [showPopup, setShowPopup] = useState(false)
  const [profile, setProfile] = useState<Record<string, unknown> | null>(null)
  const [newPassword, setNewPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [showAffiliateModal, setShowAffiliateModal] = useState(false)
  const [creatingRoom, setCreatingRoom] = useState(false)
  const [latestApp, setLatestApp] = useState<AffiliateApplicationRow | null>(null)
  const [affiliateConnectRow, setAffiliateConnectRow] = useState<AffiliateConnectRow | null>(null)

  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [bio, setBio] = useState("")
  const [isPrivate, setIsPrivate] = useState(false)

  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null)

  const [tradingStyle, setTradingStyle] = useState("")
  const [primaryMarket, setPrimaryMarket] = useState("")
  const [startedTrading, setStartedTrading] = useState("")
  const [tradingModel, setTradingModel] = useState("")
  const [maxDrawdown, setMaxDrawdown] = useState("")

  useEffect(() => {
    void init()
  }, [])

  useEffect(() => {
    const requested = String(searchParams.get("tab") ?? "")
      .toLowerCase()
      .trim()
    if (
      requested === "profile" ||
      requested === "affiliate" ||
      requested === "account" ||
      requested === "subscription"
    ) {
      setActiveTab(requested)
    }
  }, [searchParams])

  useEffect(() => {
    if (loading) return
    if (typeof window === "undefined") return
    if (window.location.hash !== "#dashboard-risk") return
    setActiveTab("account")
    const id = window.requestAnimationFrame(() => {
      document.getElementById("dashboard-risk")?.scrollIntoView({
        behavior: "smooth",
        block: "start",
      })
    })
    return () => window.cancelAnimationFrame(id)
  }, [loading])

  useEffect(() => {
    if (showPopup) {
      const timer = setTimeout(() => setShowPopup(false), 2500)
      return () => clearTimeout(timer)
    }
  }, [showPopup])

  async function fetchProfile(userId: string) {
    const { data } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .single()

    if (data) {
      setProfile(data)
      setName((data.name as string) || "")
      setUsername((data.username as string) || "")
      setBio((data.bio as string) || "")
      setIsPrivate(Boolean(data.is_private))
      setAvatarPreview((data.avatar_url as string) || null)
      setTradingStyle(
        (data.trading_style as string) || (data.trading_model as string) || ""
      )
      setPrimaryMarket((data.primary_market as string) || "")
      setTradingModel((data.trading_model as string) || "")
      setStartedTrading(sliceDateInput(data.started_trading))
      const raw = data.max_drawdown_limit
      setMaxDrawdown(
        raw != null && raw !== "" ? String(raw) : ""
      )
    }

    return data ?? null
  }

  async function refreshAffiliateState(userId: string) {
    const latest = await fetchLatestAffiliateApplication(supabase, userId)
    setLatestApp(latest)
  }

  async function refreshAffiliateConnect(userId: string) {
    const { data } = await supabase
      .from("affiliates")
      .select(AFFILIATE_CONNECT_SELECT)
      .eq("user_id", userId)
      .maybeSingle()

    let row: AffiliateConnectRow | null =
      data && typeof data === "object"
        ? parseAffiliateConnectRow(data as Record<string, unknown>)
        : null

    if (row?.stripe_connected_account_id) {
      try {
        const syncRes = await fetch("/api/affiliates/connect/sync", {
          method: "POST",
          credentials: "include",
          headers: {
            ...(await supabaseBearerHeaders()),
          },
        })
        const j = (await syncRes.json().catch(() => ({}))) as {
          affiliate?: AffiliateConnectRow | null
        }
        if (j?.affiliate) row = j.affiliate
      } catch {
        // ignore
      }
    }

    setAffiliateConnectRow(row)
  }

  async function getAccessToken(): Promise<string | null> {
    const { data: sessionData } = await supabase.auth.getSession()
    return sessionData.session?.access_token ?? null
  }

  async function init() {
    const {
      data: { user: u },
    } = await supabase.auth.getUser()

    if (!u) {
      setLoading(false)
      router.push("/login")
      return
    }

    setUser(u)

    const data = await fetchProfile(u.id)

    if (data?.id) {
      try {
        await refreshAffiliateState(data.id)
        await refreshAffiliateConnect(data.id)
      } catch (e) {
        console.error("Affiliate state refresh failed:", e)
      }
    }

    setLoading(false)
  }

  async function uploadAvatar(): Promise<string | null> {
    if (!avatarFile || !user) return null

    let uploadFile: File = avatarFile
    if (avatarFile.type?.startsWith("image/")) {
      uploadFile = await compressImage(avatarFile)
    }
    const fileName = `${user.id}/${Date.now()}-${uploadFile.name}`

    const { error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(fileName, uploadFile, { upsert: true })

    if (uploadError) {
      console.error("Avatar upload:", uploadError.message)
      return null
    }

    return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${fileName}`
  }

  async function saveProfileTab() {
    if (!user) return

    setSavingProfile(true)

    let avatarUrl = avatarPreview
    if (avatarFile) {
      const uploaded = await uploadAvatar()
      if (uploaded) avatarUrl = uploaded
    }

    const cleanUsername = username.toLowerCase().trim()

    const { error } = await supabase
      .from("profiles")
      .update({
        username: cleanUsername,
        bio,
        avatar_url: avatarUrl,
        trading_style: tradingStyle,
        primary_market: primaryMarket.trim() || null,
        trading_model: tradingModel || tradingStyle || null,
        started_trading: startedTrading.trim() || null,
      })
      .eq("id", user.id)

    setSavingProfile(false)

    if (error) {
      if (error.code === "23505" && isProfilesUsernameConflict(error)) {
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
      } else {
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
      }
      return
    }

    setUsername(cleanUsername)
    setProfile((p) =>
      p
        ? {
            ...p,
            username: cleanUsername,
            bio,
            avatar_url: avatarUrl,
            trading_style: tradingStyle,
            primary_market: primaryMarket.trim() || null,
            trading_model: tradingModel || tradingStyle || null,
            started_trading: startedTrading.trim() || null,
          }
        : p
    )
    setAvatarFile(null)
    setPopupMessage("Profile updated successfully")
    setPopupType("success")
    setShowPopup(true)
  }

  async function saveDrawdownLimit() {
    if (!user) return

    const t = maxDrawdown.trim()
    const n = t === "" ? null : Number(t)
    if (t !== "" && (!Number.isFinite(n) || n === null || n < 0)) {
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    setSavingDrawdownLimit(true)
    const { error } = await supabase
      .from("profiles")
      .update({ max_drawdown_limit: n })
      .eq("id", user.id)
    setSavingDrawdownLimit(false)

    if (error) {
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    setProfile((p) => (p ? { ...p, max_drawdown_limit: n } : p))
    setPopupMessage("Limit saved successfully")
    setPopupType("success")
    setShowPopup(true)
  }

  async function saveAccountPrivacyTab() {
    if (!user) return

    setSavingAccountPrivacy(true)
    const { error } = await supabase
      .from("profiles")
      .update({
        name: name.trim() || null,
        is_private: isPrivate,
      })
      .eq("id", user.id)
    setSavingAccountPrivacy(false)

    if (error) {
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    setProfile((p) =>
      p
        ? {
            ...p,
            name: name.trim() || null,
            is_private: isPrivate,
          }
        : p
    )
    setPopupMessage("Profile updated successfully")
    setPopupType("success")
    setShowPopup(true)
  }

  async function updatePassword() {
    if (!user) return

    if (newPassword.length < 6) {
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
      return
    }
    if (newPassword !== confirmPassword) {
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    setSavingPassword(true)
    const { error } = await supabase.auth.updateUser({
      password: newPassword,
    })
    setSavingPassword(false)

    if (error) {
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
      return
    }

    setNewPassword("")
    setConfirmPassword("")
    setPopupMessage("Password updated successfully")
    setPopupType("success")
    setShowPopup(true)
  }

  async function handleDeleteAccount() {
    setDeleting(true)

    try {
      const session = await supabase.auth.getSession()

      const res = await fetch("/api/delete-account", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.data.session?.access_token}`,
        },
      })

      if (!res.ok) {
        throw new Error("Failed")
      }

      await supabase.auth.signOut()
      window.location.href = "/login"
    } catch (err) {
      console.error(err)
      alert("Failed to delete account")
    } finally {
      setDeleting(false)
    }
  }

  async function handleExportData() {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()

      const res = await fetch("/api/export-data", {
        method: "GET",
        headers: {
          Authorization: `Bearer ${session?.access_token}`,
        },
      })

      if (!res.ok) throw new Error("Failed")

      const blob = await res.blob()
      const url = window.URL.createObjectURL(blob)

      const a = document.createElement("a")
      a.href = url
      a.download = "tradetrax_data.csv"
      a.click()

      window.URL.revokeObjectURL(url)
    } catch (err) {
      console.error(err)
      alert("Failed to export data")
    }
  }

  async function handleCreateRoom() {
    setCreatingRoom(true)

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) throw new Error("Not logged in")

      const { data: existing } = await supabase
        .from("rooms")
        .select("id, slug")
        .eq("owner_user_id", user.id)
        .maybeSingle()

      if (existing) {
        alert("You already have a Trade Room")
        return
      }

      const { data: profile } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", user.id)
        .single()

      const room = await createUserRoom(user.id, profile?.username || "user")
      const slug =
        room && typeof room === "object" && "slug" in room
          ? String((room as { slug?: string }).slug ?? "").trim()
          : ""

      if (!slug) {
        alert("Trade Room created!")
        return
      }

      router.push(
        `/trade-rooms?room=${encodeURIComponent(slug)}&setup=true`
      )
    } catch (err) {
      console.error(err)
      alert("Failed to create room")
    } finally {
      setCreatingRoom(false)
    }
  }

  async function startTraxProCheckout() {
    if (!user) return

    setCheckoutLoading(true)
    try {
      const token = await getAccessToken()
      if (!token) {
        router.push("/login?next=checkout")
        return
      }

      const res = await fetch("/api/create-checkout-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          userId: user.id,
          referralCode:
            typeof window !== "undefined"
              ? localStorage.getItem("referral_code")
              : null,
        }),
      })

      const data = await res.json().catch(() => ({}))

      if (!res.ok) {
        console.error("Settings checkout failed:", { status: res.status, data })
        if (res.status === 401) {
          setPopupMessage("Something went wrong")
          setPopupType("error")
          setShowPopup(true)
          router.push("/login?next=checkout")
          return
        }
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
        return
      }

      if (data.url) {
        window.location.href = data.url as string
      } else {
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
      }
    } catch (e) {
      console.error(e)
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
    } finally {
      setCheckoutLoading(false)
    }
  }

  async function openStripeSubscriptionPortal() {
    if (!user) return

    setManageLoading(true)
    try {
      const token = await getAccessToken()
      if (!token) {
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
        router.push("/login")
        return
      }

      const res = await fetch("/api/create-portal-session", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
      })

      const data = await res.json().catch(() => ({}))

      if (!res.ok) {
        console.error("Settings portal failed:", { status: res.status, data })
        if (res.status === 401) {
          setPopupMessage("Something went wrong")
          setPopupType("error")
          setShowPopup(true)
          router.push("/login")
          return
        }
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
        return
      }

      if (data.url) {
        window.location.href = data.url as string
      } else {
        setPopupMessage("Something went wrong")
        setPopupType("error")
        setShowPopup(true)
      }
    } catch (e) {
      console.error(e)
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
    } finally {
      setManageLoading(false)
    }
  }

  const referralCode =
    profile?.referral_code != null && String(profile.referral_code).trim() !== ""
      ? String(profile.referral_code)
      : ""

  const referralLink =
    typeof window !== "undefined" && referralCode
      ? `${window.location.origin}?ref=${referralCode}`
      : ""

  const referralCount = Number(profile?.referral_count ?? 0)
  const COMMISSION_RATE = 0.18
  const PLAN_PRICE = 15.99
  const earnings = referralCount * PLAN_PRICE * COMMISSION_RATE

  const isAffiliatePending = latestApp?.status === "pending"
  const affiliateApplicationLocked = Boolean(
    isAffiliatePending && latestApp?.has_edited
  )

  const showAffiliateApplyCta = Boolean(
    user &&
      !isAffiliatePending &&
      !String(referralCode).trim() &&
      (!latestApp || latestApp.status === "rejected")
  )

  const showAffiliatePayoutSetup = Boolean(
    String(referralCode).trim() ||
      latestApp?.status === "approved" ||
      affiliateConnectRow?.id
  )

  async function copyReferralLink() {
    if (!referralLink) return
    try {
      await navigator.clipboard.writeText(referralLink)
      setPopupMessage("Copied!")
      setPopupType("success")
      setShowPopup(true)
    } catch (err) {
      console.error("Copy failed", err)
      setPopupMessage("Something went wrong")
      setPopupType("error")
      setShowPopup(true)
    }
  }

  async function afterAffiliateModalSubmit() {
    if (!user) return
    setShowAffiliateModal(false)
    await fetchProfile(user.id)
    await refreshAffiliateState(user.id)
    await refreshAffiliateConnect(user.id)
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-6 text-center text-white">
          Loading…
        </div>
      </>
    )
  }

  const activeMeta = TABS.find((t) => t.id === activeTab)!
  const rawStatus = String(profile?.subscription_status ?? "").toLowerCase().trim()
  const displayStatus = rawStatus || "inactive"
  const isSubscribed =
    displayStatus === "active" ||
    displayStatus === "trialing" ||
    isProActive(profile)

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">
        <div className="mx-auto flex max-w-6xl flex-col gap-6 md:flex-row md:items-start">
          {/* LEFT — tabs */}
          <aside className="w-full shrink-0 md:w-64">
            <h1 className="mb-2 text-xl font-semibold text-white md:text-2xl">
              Settings
            </h1>
            <p className="mb-4 text-sm text-gray-400">
              Plan: {isProActive(profile as any) ? "Pro" : "Free"}
            </p>
            <nav className="flex flex-row gap-2 overflow-x-auto pb-2 md:flex-col md:gap-1 md:overflow-visible md:pb-0">
              {TABS.map((tab) => (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => setActiveTab(tab.id)}
                  className={`rounded-xl px-4 py-3 text-left transition md:w-full ${
                    activeTab === tab.id
                      ? "bg-white/15 ring-1 ring-blue-400/50"
                      : "bg-white/5 hover:bg-white/10"
                  }`}
                >
                  <span className="block font-medium text-white">{tab.label}</span>
                  <span className="mt-0.5 hidden text-xs text-gray-400 md:block">
                    {tab.description}
                  </span>
                </button>
              ))}
            </nav>
          </aside>

          {/* RIGHT — content */}
          <div className="min-w-0 flex-1">
            <div className="mb-6">
              <h2 className="text-lg font-semibold text-blue-200">
                {activeMeta.label}
              </h2>
              <p className="mt-1 text-sm text-gray-400">{activeMeta.description}</p>
            </div>

            {activeTab === "profile" && (
              <div className="space-y-6 rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                <div className="flex flex-wrap items-center gap-4">
                  <div className="h-16 w-16 shrink-0 overflow-hidden rounded-full bg-gray-700">
                    {avatarPreview ? (
                      <img
                        src={avatarPreview}
                        alt=""
                        className="h-full w-full object-cover"
                        onError={(e) => {
                          e.currentTarget.src = "/default-avatar.png"
                        }}
                      />
                    ) : null}
                  </div>
                  <input
                    type="file"
                    accept="image/*"
                    onChange={(e) => {
                      const file = e.target.files?.[0]
                      if (!file) return
                      setAvatarFile(file)
                      setAvatarPreview(URL.createObjectURL(file))
                    }}
                    className="max-w-full text-sm text-gray-300 file:mr-2 file:rounded-lg file:border-0 file:bg-white/10 file:px-3 file:py-2 file:text-sm file:text-gray-100 hover:file:bg-white/20"
                  />
                </div>

                <input
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Username"
                  className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                />

                <textarea
                  value={bio}
                  onChange={(e) => setBio(e.target.value)}
                  placeholder="Bio"
                  rows={4}
                  className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                />

                <div>
                  <label className="mb-1 block text-sm text-gray-400">
                    Trading style
                  </label>
                  <input
                    value={tradingModel}
                    onChange={(e) => {
                      setTradingModel(e.target.value)
                      setTradingStyle(e.target.value)
                    }}
                    placeholder="e.g. ICT, scalping, swing"
                    className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-sm text-gray-400">
                    Primary Market
                  </label>
                  <input
                    value={primaryMarket}
                    onChange={(e) => setPrimaryMarket(e.target.value)}
                    placeholder="e.g. NQ, ES, Gold, BTC, EUR/USD"
                    className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-sm text-gray-400">
                    Started Trading Date
                  </label>
                  <input
                    type="date"
                    value={startedTrading}
                    onChange={(e) => setStartedTrading(e.target.value)}
                    className="w-full rounded-xl border border-white/10 bg-[#0f172a] p-3"
                  />
                </div>

                <button
                  type="button"
                  onClick={() => void saveProfileTab()}
                  disabled={savingProfile}
                  className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 py-3 font-semibold disabled:opacity-50"
                >
                  {savingProfile ? "Saving…" : "Save profile"}
                </button>
              </div>
            )}
            {activeTab === "affiliate" && (
              <div className="space-y-6 rounded-2xl border border-white/10 bg-white/5 p-4 backdrop-blur-sm">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h3 className="text-lg font-semibold text-white">Affiliate program</h3>
                    <p className="mt-1 text-sm text-gray-400">
                      Apply, track status, and manage your referral link.{" "}
                      <a
                        href="/affiliate"
                        className="text-blue-300 underline hover:text-blue-200"
                      >
                        Open Affiliate Dashboard
                      </a>
                      {" · "}
                      <a href="/payouts" className="text-blue-300 underline hover:text-blue-200">
                        Payouts
                      </a>
                    </p>
                  </div>
                  {(showAffiliateApplyCta || isAffiliatePending) && (
                    <button
                      type="button"
                      onClick={() => setShowAffiliateModal(true)}
                      className={
                        affiliateApplicationLocked
                          ? "shrink-0 rounded-xl bg-white/10 px-4 py-2 text-sm font-semibold text-white/60 hover:bg-white/15"
                          : "shrink-0 rounded-xl bg-gradient-to-r from-emerald-500 to-blue-500 px-4 py-2 text-sm font-semibold text-white shadow-lg hover:opacity-95"
                      }
                    >
                      {affiliateApplicationLocked
                        ? "View Application"
                        : isAffiliatePending
                          ? "Edit Application"
                          : "Apply to be an Affiliate"}
                    </button>
                  )}
                </div>

                {isAffiliatePending ? (
                  <div className="rounded-xl border border-amber-500/35 bg-amber-500/10 px-4 py-3 text-sm text-amber-50">
                    <p className="font-medium text-white">Application status: pending</p>
                    <p className="mt-1 text-amber-100/90">
                      We&apos;ll email you at {user?.email ?? "your account email"} when there&apos;s
                      an update.
                      {!latestApp?.has_edited
                        ? " You have one edit available before your application is locked."
                        : ""}
                    </p>
                    {latestApp?.has_edited ? (
                      <p className="mt-2 text-xs text-amber-200/90">
                        You have already used your one edit.
                      </p>
                    ) : null}
                  </div>
                ) : latestApp?.status === "rejected" ? (
                  <div className="rounded-xl border border-red-500/35 bg-red-500/10 px-4 py-3 text-sm text-red-100">
                    <p className="font-medium text-white">Application status: rejected</p>
                    <p className="mt-1 text-red-100/90">
                      Your last application wasn&apos;t approved. You can submit a new one when
                      you&apos;re ready.
                    </p>
                  </div>
                ) : latestApp?.status === "approved" && referralCode ? (
                  <div className="rounded-xl border border-emerald-500/35 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-50">
                    <p className="font-medium text-white">Application status: approved</p>
                    <p className="mt-1 text-emerald-100/90">
                      You&apos;re active as an affiliate. Your code is{" "}
                      <span className="font-mono font-semibold text-white">{referralCode}</span>.
                    </p>
                  </div>
                ) : null}

                <div className="mb-4">
                  <AffiliatePayoutSetupCard
                    affiliateConnect={affiliateConnectRow}
                    show={showAffiliatePayoutSetup}
                  />
                </div>

                {!referralCode ? (
                  <p className="text-sm text-gray-400">
                    {isAffiliatePending
                      ? "When approved, your referral code and share link will show here."
                      : "Submit an application to request access. When approved, your referral code and link will appear here and on the Affiliate Dashboard."}
                  </p>
                ) : (
                  <>
                    <div className="grid gap-4 sm:grid-cols-2">
                      <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                        <p className="text-xs text-gray-400">Referral code</p>
                        <p className="mt-1 break-all text-lg font-semibold text-blue-300">
                          {referralCode}
                        </p>
                      </div>
                      <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                        <p className="text-xs text-gray-400">Total referrals</p>
                        <p className="mt-1 text-2xl font-bold text-white">
                          {referralCount}
                        </p>
                      </div>
                    </div>

                    <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                      <p className="text-xs text-gray-400">Earnings</p>
                      <p className="mt-1 text-2xl font-bold text-emerald-400">
                        ${earnings.toFixed(2)}
                      </p>
                    </div>

                    <div>
                      <p className="mb-2 text-sm text-gray-400">Referral link</p>
                      <div className="flex flex-col gap-2 sm:flex-row">
                        <input
                          value={referralLink}
                          readOnly
                          className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/30 p-3 text-sm"
                        />
                        <button
                          type="button"
                          onClick={() => void copyReferralLink()}
                          className="shrink-0 rounded-xl bg-emerald-500 px-5 py-3 text-sm font-semibold hover:bg-emerald-600"
                        >
                          Copy link
                        </button>
                      </div>
                    </div>
                  </>
                )}
              </div>
            )}

            {activeTab === "account" && (
              <div className="space-y-8">
                <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                    Login
                  </h3>
                  <p className="mt-1 text-sm text-gray-400">
                    Email tied to your TradeTraxs account
                  </p>
                  <div className="mt-4">
                    <label className="text-xs text-gray-500">Email</label>
                    <p className="mt-1 break-all rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-white">
                      {user?.email ?? "—"}
                    </p>
                  </div>
                </section>

                <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                    Display & privacy
                  </h3>
                  <p className="mt-1 text-sm text-gray-400">
                    How your name appears and who can view your profile
                  </p>
                  <input
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Display name"
                    className="mt-4 w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                  <div className="mt-4 flex flex-col gap-3 rounded-xl border border-white/10 bg-black/20 p-4 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <p className="font-medium text-white">Private profile</p>
                      <p className="text-xs text-gray-400">
                        Only followers can view your full profile
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => setIsPrivate(!isPrivate)}
                      className={`shrink-0 rounded-lg px-4 py-2 text-sm font-medium transition ${
                        isPrivate
                          ? "bg-emerald-500 text-white"
                          : "bg-white/10 text-white"
                      }`}
                    >
                      {isPrivate ? "On" : "Off"}
                    </button>
                  </div>
                  <button
                    type="button"
                    onClick={() => void saveAccountPrivacyTab()}
                    disabled={savingAccountPrivacy}
                    className="mt-4 w-full rounded-xl bg-white/10 py-3 font-semibold hover:bg-white/15 disabled:opacity-50"
                  >
                    {savingAccountPrivacy ? "Saving…" : "Save display & privacy"}
                  </button>
                </section>

                <section
                  id="dashboard-risk"
                  className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
                >
                  <div className="flex items-center gap-2">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      className="shrink-0 text-blue-300"
                      aria-hidden
                    >
                      <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
                      <circle cx="12" cy="12" r="3" />
                    </svg>
                    <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                      Dashboard & risk
                    </h3>
                  </div>
                  <p className="mt-1 text-sm text-gray-400">
                    Controls how drawdown warnings appear on your dashboard (same as the gear
                    menu).
                  </p>
                  <div className="mt-4 flex flex-col gap-3 rounded-xl border border-white/10 bg-black/20 p-4 sm:flex-row sm:items-end sm:justify-between">
                    <div className="min-w-0 flex-1">
                      <label
                        htmlFor="max-drawdown-limit"
                        className="text-sm font-medium text-white"
                      >
                        Max drawdown limit
                      </label>
                      <p className="mt-1 text-xs text-gray-500">
                        Optional cap from your equity peak. Leave blank to clear.
                      </p>
                      <input
                        id="max-drawdown-limit"
                        type="number"
                        min={0}
                        step="0.01"
                        placeholder="Max drawdown ($)"
                        value={maxDrawdown}
                        onChange={(e) => setMaxDrawdown(e.target.value)}
                        className="mt-3 w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                      />
                    </div>
                    <button
                      type="button"
                      onClick={() => void saveDrawdownLimit()}
                      disabled={savingDrawdownLimit}
                      className="shrink-0 rounded-lg bg-white/10 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-white/15 disabled:opacity-50 sm:mb-0"
                    >
                      {savingDrawdownLimit ? "Saving…" : "Save limit"}
                    </button>
                  </div>
                </section>

                <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                    Change password
                  </h3>
                  <p className="mt-1 text-sm text-gray-400">
                    Choose a strong password you have not used elsewhere
                  </p>
                  <input
                    type="password"
                    autoComplete="new-password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="New password"
                    className="mt-4 w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                  <input
                    type="password"
                    autoComplete="new-password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="Confirm password"
                    className="mt-4 w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                  <button
                    type="button"
                    onClick={() => void updatePassword()}
                    disabled={savingPassword}
                    className="mt-4 w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 py-3 font-semibold disabled:opacity-50"
                  >
                    {savingPassword ? "Updating…" : "Update password"}
                  </button>

                  <div className="mt-6 flex gap-3">
                    <button
                      type="button"
                      onClick={() => {
                        setConfirmText("")
                        setShowDeleteConfirm(true)
                      }}
                      className="rounded-lg bg-red-500/10 px-5 py-2 text-red-400 hover:bg-red-500/20"
                    >
                      Delete Account
                    </button>

                    <button
                      type="button"
                      onClick={() => void handleExportData()}
                      className="rounded-lg bg-blue-500/10 px-4 py-2 text-blue-400 hover:bg-blue-500/20"
                    >
                      Export My Data (CSV)
                    </button>
                  </div>
                </section>
              </div>
            )}

            {activeTab === "subscription" && (
              <div className="space-y-6 rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                <div className="space-y-4">
                  <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                    <p className="text-xs text-gray-500">Plan name</p>
                    <p className="mt-1 font-semibold text-white">
                      {profile?.is_pro === true
                        ? "TraxPro ($16.99/month)"
                        : "Free Plan"}
                    </p>
                  </div>

                  <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                    <p className="text-xs text-gray-500">Status</p>
                    <p className="text-sm text-gray-400">
                      Membership: {getMembershipStatus(profile)}
                    </p>
                  </div>

                  <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                    <p className="text-xs text-gray-500">Customer ID</p>
                    <p className="mt-1 font-mono text-sm text-gray-200">
                      {formatStripeCustomerId(profile?.stripe_customer_id)}
                    </p>
                  </div>
                </div>

                <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                  <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                    Feature access
                  </p>
                  <ul className="mt-3 space-y-2">
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>Full Dashboard</span>
                      <span aria-hidden>
                        {profile?.is_pro === true ? "✅" : "❌"}
                      </span>
                    </li>
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>AI Analyst</span>
                      <span aria-hidden>
                        {profile?.is_pro === true ? "✅" : "❌"}
                      </span>
                    </li>
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>Multiple Accounts</span>
                      <span aria-hidden>
                        {profile?.is_pro === true ? "✅" : "❌"}
                      </span>
                    </li>
                  </ul>
                </div>

                {!isSubscribed ? (
                  <button
                    type="button"
                    onClick={() => void startTraxProCheckout()}
                    disabled={checkoutLoading}
                    className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 py-3 font-semibold disabled:opacity-50"
                  >
                    {checkoutLoading ? "Redirecting…" : "Upgrade to TraxPro"}
                  </button>
                ) : null}

                {isSubscribed || profile?.stripe_customer_id ? (
                  <div className="border-t border-white/10 pt-6">
                    <button
                      type="button"
                      onClick={() => void openStripeSubscriptionPortal()}
                      disabled={manageLoading}
                      className="w-full rounded-xl bg-white/10 py-3 font-semibold text-white hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      {manageLoading ? "Opening…" : "Manage / Cancel Subscription"}
                    </button>
                    <p className="mt-3 text-center text-xs text-gray-400">
                      Subscription changes and cancellation are handled securely in
                      Stripe Customer Portal.
                    </p>
                  </div>
                ) : null}
              </div>
            )}
          </div>
        </div>
      </div>

      <AffiliateApplyModal
        open={showAffiliateModal}
        onClose={() => setShowAffiliateModal(false)}
        onSubmit={() => void afterAffiliateModalSubmit()}
        prefillFrom={latestApp}
        title={
          affiliateApplicationLocked
            ? "View application"
            : "Affiliate application"
        }
      />
      {showDeleteConfirm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
          <div className="w-full max-w-md rounded-xl bg-[#0f172a] p-6">
            <h2 className="mb-2 text-lg font-semibold text-red-400">Delete Account</h2>
            <p className="mb-4 text-sm text-gray-400">
              This action is permanent and cannot be undone.
            </p>
            <input
              type="text"
              placeholder='Type "DELETE" to confirm'
              value={confirmText}
              onChange={(e) => setConfirmText(e.target.value)}
              className="mt-3 w-full rounded-lg border border-white/10 bg-[#020617] px-3 py-2 text-sm"
            />

            <div className="flex justify-end gap-3">
              <button
                type="button"
                onClick={() => {
                  setShowDeleteConfirm(false)
                  setConfirmText("")
                }}
                className="px-3 py-1 text-gray-400"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={() => void handleDeleteAccount()}
                disabled={confirmText !== "DELETE" || deleting}
                className={`rounded-lg px-4 py-2 ${
                  confirmText === "DELETE"
                    ? "bg-red-500 text-white"
                    : "cursor-not-allowed bg-gray-700 text-gray-400"
                }`}
              >
                {deleting ? "Deleting..." : "Confirm Delete"}
              </button>
            </div>
          </div>
        </div>
      )}
      {showPopup && (
        <div className="fixed inset-0 flex items-center justify-center z-50">
          <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
          <div
            className={`relative w-full max-w-sm rounded-xl border px-6 py-5 text-center shadow-xl ${
              popupType === "success" ? "border-green-500 bg-green-900/20" : "border-red-500 bg-red-900/20"
            }`}
          >
            <p className={`text-sm font-medium ${popupType === "success" ? "text-green-400" : "text-red-400"}`}>
              {popupMessage}
            </p>
            <button
              type="button"
              onClick={() => setShowPopup(false)}
              className="mt-4 text-xs text-gray-400 hover:underline"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </>
  )
}
