"use client"

import Navbar from "../components/Navbar"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import { isProActive } from "../../lib/subscription"
import type { User } from "@supabase/supabase-js"

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
    description: "Public profile, trading style, and risk limits",
  },
  {
    id: "affiliate",
    label: "Affiliate",
    description: "Referrals, links, and earnings",
  },
]

export default function SettingsPage() {
  const router = useRouter()
  const [activeTab, setActiveTab] = useState<TabId>("account")

  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)
  const [savingProfile, setSavingProfile] = useState(false)
  const [savingAccountPrivacy, setSavingAccountPrivacy] = useState(false)
  const [savingPassword, setSavingPassword] = useState(false)
  const [manageLoading, setManageLoading] = useState(false)
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const [profile, setProfile] = useState<Record<string, unknown> | null>(null)
  const [newPassword, setNewPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [affiliateData, setAffiliateData] = useState<{
    code?: string
    id?: string
  } | null>(null)
  const [showAffiliateModal, setShowAffiliateModal] = useState(false)
  const [existingApp, setExistingApp] = useState<{ id: string; status?: string | null } | null>(
    null
  )
  const [experience, setExperience] = useState("")
  const [socialHandle, setSocialHandle] = useState("")
  const [why, setWhy] = useState("")

  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [bio, setBio] = useState("")
  const [isPrivate, setIsPrivate] = useState(false)

  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null)

  const [tradingStyle, setTradingStyle] = useState("")
  const [startedTrading, setStartedTrading] = useState("")
  const [tradingModel, setTradingModel] = useState("")
  const [maxDrawdown, setMaxDrawdown] = useState("")

  useEffect(() => {
    void init()
  }, [])

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
      setTradingModel((data.trading_model as string) || "")
      setStartedTrading(sliceDateInput(data.started_trading))
      const raw = data.max_drawdown_limit
      setMaxDrawdown(
        raw != null && raw !== "" ? String(raw) : ""
      )
    }

    return data ?? null
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

    if (data) {
      try {
        const { data: affiliate } = await supabase
          .from("affiliates")
          .select("*")
          .eq("user_id", data.id)
          .single()

        if (affiliate) setAffiliateData(affiliate as { code?: string; id?: string })
      } catch (e) {
        console.error("Affiliate stats fetch failed:", e)
      }

      try {
        const { data: appRow, error: appErr } = await supabase
          .from("affiliate_applications")
          .select("id, status")
          .eq("user_id", data.id)
          .maybeSingle()

        if (appErr) {
          console.error("Affiliate application fetch failed:", appErr)
        } else {
          setExistingApp((appRow as { id: string; status?: string | null } | null) ?? null)
        }
      } catch (e) {
        console.error("Affiliate application fetch failed:", e)
      }
    }

    setLoading(false)
  }

  async function uploadAvatar(): Promise<string | null> {
    if (!avatarFile || !user) return null

    const fileExt = avatarFile.name.split(".").pop()
    const fileName = `${user.id}/${Date.now()}.${fileExt}`

    const { error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(fileName, avatarFile, { upsert: true })

    if (uploadError) {
      console.error("Avatar upload:", uploadError.message)
      return null
    }

    return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${fileName}`
  }

  async function saveProfileTab() {
    if (!user) return

    const t = maxDrawdown.trim()
    const n = t === "" ? null : Number(t)
    if (t !== "" && (!Number.isFinite(n) || n === null || n < 0)) {
      alert("Enter a valid non-negative dollar amount for drawdown limit, or leave blank to clear.")
      return
    }

    setSavingProfile(true)

    let avatarUrl = avatarPreview
    if (avatarFile) {
      const uploaded = await uploadAvatar()
      if (uploaded) avatarUrl = uploaded
    }

    const { error } = await supabase
      .from("profiles")
      .update({
        username,
        bio,
        avatar_url: avatarUrl,
        trading_style: tradingStyle,
        trading_model: tradingModel || tradingStyle || null,
        started_trading: startedTrading.trim() || null,
        max_drawdown_limit: n,
      })
      .eq("id", user.id)

    setSavingProfile(false)

    if (error) {
      alert(error.message)
      return
    }

    setProfile((p) =>
      p
        ? {
            ...p,
            username,
            bio,
            avatar_url: avatarUrl,
            trading_style: tradingStyle,
            trading_model: tradingModel || tradingStyle || null,
            started_trading: startedTrading.trim() || null,
            max_drawdown_limit: n,
          }
        : p
    )
    setAvatarFile(null)
    alert("Profile saved")
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
      alert(error.message)
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
    alert("Account preferences saved")
  }

  async function updatePassword() {
    if (!user) return

    if (newPassword.length < 6) {
      alert("Password must be at least 6 characters.")
      return
    }
    if (newPassword !== confirmPassword) {
      alert("Passwords do not match.")
      return
    }

    setSavingPassword(true)
    const { error } = await supabase.auth.updateUser({
      password: newPassword,
    })
    setSavingPassword(false)

    if (error) {
      alert(error.message)
      return
    }

    setNewPassword("")
    setConfirmPassword("")
    alert("Password updated")
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
          alert("Session expired. Please sign in again.")
          router.push("/login?next=checkout")
          return
        }
        alert(typeof data.error === "string" ? data.error : "Checkout failed")
        return
      }

      if (data.url) {
        window.location.href = data.url as string
      } else {
        alert(typeof data.error === "string" ? data.error : "Checkout failed")
      }
    } catch (e) {
      console.error(e)
      alert("Checkout failed")
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
        alert("Session expired. Please sign in again.")
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
          alert("Session expired. Please sign in again.")
          router.push("/login")
          return
        }
        alert(
          typeof data.error === "string"
            ? data.error
            : "Unable to open billing portal"
        )
        return
      }

      if (data.url) {
        window.location.href = data.url as string
      } else {
        alert("Unable to open billing portal")
      }
    } catch (e) {
      console.error(e)
      alert("Something went wrong")
    } finally {
      setManageLoading(false)
    }
  }

  const referralCode =
    (profile?.referral_code != null &&
    String(profile.referral_code).trim() !== ""
      ? String(profile.referral_code)
      : null) ||
    affiliateData?.code ||
    ""

  const referralLink =
    typeof window !== "undefined" && referralCode
      ? `${window.location.origin}?ref=${referralCode}`
      : ""

  const referralCount = Number(profile?.referral_count ?? 0)
  const COMMISSION_RATE = 0.18
  const PLAN_PRICE = 15.99
  const earnings = referralCount * PLAN_PRICE * COMMISSION_RATE

  async function copyReferralLink() {
    if (!referralLink) return
    try {
      await navigator.clipboard.writeText(referralLink)
      alert("Copied!")
    } catch (err) {
      console.error("Copy failed", err)
      alert("Failed to copy")
    }
  }

  async function submitApplication() {
    if (!user) return

    const { data: inserted, error } = await supabase
      .from("affiliate_applications")
      .insert({
        user_id: user.id,
        experience,
        social_handle: socialHandle,
        why,
      })
      .select("id, status")
      .single()

    if (error) {
      console.error("Affiliate application submit failed:", error)
      return
    }

    setExistingApp((inserted as { id: string; status?: string | null }) ?? null)
    setShowAffiliateModal(false)
    setExperience("")
    setSocialHandle("")
    setWhy("")
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
                    Started Trading Date
                  </label>
                  <input
                    type="date"
                    value={startedTrading}
                    onChange={(e) => setStartedTrading(e.target.value)}
                    className="w-full rounded-xl border border-white/10 bg-[#0f172a] p-3"
                  />
                </div>

                <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                  <p className="text-sm font-medium text-white">Drawdown limit</p>
                  <p className="mt-1 text-xs text-gray-500">
                    Optional cap from your equity peak (used on the dashboard). Leave blank
                    to clear.
                  </p>
                  <input
                    type="number"
                    min={0}
                    step="0.01"
                    placeholder="Max drawdown ($)"
                    value={maxDrawdown}
                    onChange={(e) => setMaxDrawdown(e.target.value)}
                    className="mt-3 w-full rounded-xl border border-white/10 bg-[#0f172a] p-3"
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
              <div className="space-y-6 rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                {!referralCode ? (
                  <p className="text-sm text-gray-400">
                    No referral code on file yet. Visit the{" "}
                    <a
                      href="/affiliate"
                      className="text-blue-300 underline hover:text-blue-200"
                    >
                      Affiliate Dashboard
                    </a>{" "}
                    to get set up.
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

                <div className="mt-6">
                  <h3 className="text-lg font-semibold text-white mb-2">Affiliate Program</h3>
                  {existingApp ? (
                    <>
                      <p className="text-sm text-white/70">
                        Application Status: {existingApp.status || "submitted"}
                      </p>
                      <button
                        type="button"
                        disabled
                        className="mt-3 bg-green-500 hover:bg-green-600 px-4 py-2 rounded text-white opacity-50 cursor-not-allowed"
                      >
                        Application Submitted
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setShowAffiliateModal(true)}
                      className="bg-green-500 hover:bg-green-600 px-4 py-2 rounded text-white"
                    >
                      Apply to be an Affiliate
                    </button>
                  )}
                </div>
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
                    <p
                      className={`mt-1 font-semibold capitalize ${subscriptionStatusClass(
                        displayStatus
                      )}`}
                    >
                      {displayStatus}
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

      {showAffiliateModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50">
          <div className="bg-[#1e2a4a] p-6 rounded-xl w-[400px]">
            <h2 className="text-white text-lg mb-4">Affiliate Application</h2>

            <textarea
              placeholder="Your experience trading or promoting..."
              value={experience}
              onChange={(e) => setExperience(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-400"
            />
            <input
              placeholder="Social handle (optional)"
              value={socialHandle}
              onChange={(e) => setSocialHandle(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-400"
            />
            <textarea
              placeholder="Why should we accept you?"
              value={why}
              onChange={(e) => setWhy(e.target.value)}
              className="w-full rounded border border-white/10 bg-[#0f172a] p-2 text-sm text-white placeholder:text-gray-400"
            />

            <div className="flex justify-end gap-2 mt-4">
              <button
                type="button"
                onClick={() => setShowAffiliateModal(false)}
                className="rounded bg-white/10 px-3 py-1.5 text-sm text-white hover:bg-white/20"
              >
                Cancel
              </button>

              <button
                type="button"
                onClick={() => void submitApplication()}
                className="rounded bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
              >
                Submit
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
