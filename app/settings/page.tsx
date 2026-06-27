"use client"

import { SkeletonSettingsPage } from "../components/ui/skeletons"

import Navbar from "../components/Navbar"
import AffiliateApplyModal from "../components/AffiliateApplyModal"
import { useEffect, useLayoutEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import {
  formatSubscriptionDateTime,
  formatScheduledCancellation,
  getMembershipStatus,
  shouldShowScheduledCancellation,
  shouldShowTrialInfo,
} from "@/lib/getMembershipStatus"
import { isProActive } from "../../lib/subscription"
import {
  TRAXPRO_BILLING_LABEL,
  TRAXPRO_PLAN_NAME,
  TRAXPRO_PRICE_DISPLAY,
} from "@/lib/traxProPricing"
import {
  canChangeProfileUsername,
  isProfilesUsernameConflict,
  MAX_PROFILE_USERNAME_CHANGES,
  normalizeProfileUsername,
  profileUsernamesEqual,
  sanitizeUsernameInputForTyping,
  usernameChangesRemaining,
  validateProfileUsernameNotEmpty,
} from "@/lib/profileUsername"
import { TRADER_TYPE_OPTIONS } from "@/lib/traderType"
import { mirrorAccountSettingsUsernameChangeCount } from "@/lib/profileSplitMirrorWrites"

import AffiliatePayoutSetupCard from "@/app/components/AffiliatePayoutSetupCard"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { fetchLatestAffiliateApplication, type AffiliateApplicationRow } from "@/lib/affiliateApplication"
import {
  AFFILIATE_CONNECT_SELECT,
  parseAffiliateConnectRow,
  type AffiliateConnectRow,
} from "@/lib/affiliateStripeConnect"
import { createUserRoom } from "@/lib/createUserRoom"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import {
  getLocalTodayDateInputValue,
  isStartedTradingDateInFuture,
} from "@/lib/tradeDateValidation"
import TradingAccountsSettingsSection from "@/app/components/TradingAccountsSettingsSection"
import { useUserProfile } from "@/lib/UserProfileProvider"
import {
  buildSettingsFormSeed,
  fetchSettingsProfileRow,
  mergeSettingsProfileSources,
  persistSettingsProfileEverywhere,
  settingsSaveToSharedSlice,
  sharedSliceToSettingsRow,
  sliceDateInput,
} from "@/lib/settingsProfileSync"
import { readSettingsProfileCache } from "@/lib/settingsProfileCache"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { useAutoResizeTextarea } from "@/lib/useAutoResizeTextarea"
import { getPasswordManagementMode } from "@/lib/authPasswordManagement"

type TabId =
  | "profile"
  | "affiliate"
  | "account"
  | "subscription"
  | "trading-accounts"

function resolveSettingsTabFromHash(hash: string): TabId | null {
  const requested = hash.replace("#", "").toLowerCase().trim()
  if (
    requested === "profile" ||
    requested === "affiliate" ||
    requested === "account" ||
    requested === "subscription"
  ) {
    return requested
  }
  if (
    requested === "trading-accounts" ||
    requested === "rules" ||
    requested === "dashboard-risk"
  ) {
    return "trading-accounts"
  }
  return null
}

function profileDateExists(raw: unknown): boolean {
  if (raw == null || raw === "") return false
  return !Number.isNaN(new Date(String(raw)).getTime())
}

function applySettingsFormSeed(
  seed: ReturnType<typeof buildSettingsFormSeed>,
  setters: {
    setName: (v: string) => void
    setUsername: (v: string) => void
    setBio: (v: string) => void
    setIsPrivate: (v: boolean) => void
    setAvatarPreview: (v: string | null) => void
    setTradingStyle: (v: string) => void
    setTraderType: (v: string) => void
    setPrimaryMarket: (v: string) => void
    setTradingModel: (v: string) => void
    setStartedTrading: (v: string) => void
  }
) {
  if (!seed) return
  setters.setName(seed.name)
  setters.setUsername(seed.username)
  setters.setBio(seed.bio)
  setters.setIsPrivate(seed.isPrivate)
  setters.setAvatarPreview(seed.avatarPreview)
  setters.setTradingStyle(seed.tradingStyle)
  setters.setTraderType(seed.traderType)
  setters.setPrimaryMarket(seed.primaryMarket)
  setters.setTradingModel(seed.tradingModel)
  setters.setStartedTrading(seed.startedTrading)
}

function shouldShowRenewsOn(profile: Record<string, unknown> | null): boolean {
  if (!profile) return false
  if (shouldShowScheduledCancellation(profile)) return false
  const status = String(profile.subscription_status ?? "").toLowerCase().trim()
  if (status !== "active") return false
  if (profile.cancel_at_period_end === true) return false
  return profileDateExists(profile.current_period_end)
}

const TABS: {
  id: TabId
  label: string
  description: string
}[] = [
  {
    id: "account",
    label: "Account",
    description: "Login, security, and data",
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
    id: "trading-accounts",
    label: "Trading Accounts",
    description: "Manage active accounts and account types",
  },
  {
    id: "affiliate",
    label: "Affiliate",
    description: "Referrals, links, and earnings",
  },
]

export default function SettingsPage() {
  const router = useRouter()
  useScrollPageTopOnMount()
  const [activeTab, setActiveTab] = useState<TabId>("account")

  const { user, profile: sharedProfile, loading: profileLoading, setProfile: setSharedProfile } =
    useUserProfile()
  const [profile, setProfile] = useState<Record<string, unknown> | null>(null)
  const [savingProfile, setSavingProfile] = useState(false)
  const savingProfileRef = useRef(false)
  const formSeededRef = useRef(false)
  const [savingPassword, setSavingPassword] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [confirmText, setConfirmText] = useState("")
  const [manageLoading, setManageLoading] = useState(false)
  const [checkoutLoading, setCheckoutLoading] = useState(false)
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [newPassword, setNewPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [showAffiliateModal, setShowAffiliateModal] = useState(false)
  const [creatingRoom, setCreatingRoom] = useState(false)
  const [latestApp, setLatestApp] = useState<AffiliateApplicationRow | null>(null)
  const [affiliateConnectRow, setAffiliateConnectRow] = useState<AffiliateConnectRow | null>(null)

  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [bio, setBio] = useState("")
  const bioTextareaRef = useAutoResizeTextarea(bio, { minLines: 3, maxLines: 3 })
  const [isPrivate, setIsPrivate] = useState(false)

  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [avatarPreview, setAvatarPreview] = useState<string | null>(null)

  const [tradingStyle, setTradingStyle] = useState("")
  const [traderType, setTraderType] = useState("")
  const [primaryMarket, setPrimaryMarket] = useState("")
  const [startedTrading, setStartedTrading] = useState("")
  const [tradingModel, setTradingModel] = useState("")

  const invalidStartedTradingDate = isStartedTradingDateInFuture(startedTrading)
  const localTodayDate = getLocalTodayDateInputValue()
  const passwordManagementMode = getPasswordManagementMode(user)
  const isCreatePasswordFlow = passwordManagementMode === "create"

  function handleStartedTradingChange(next: string) {
    if (isStartedTradingDateInFuture(next)) {
      showPopup(feedbackPresets.invalidStartedTradingDate())
    }
    setStartedTrading(next)
  }

  const formSetters = {
    setName,
    setUsername,
    setBio,
    setIsPrivate,
    setAvatarPreview,
    setTradingStyle,
    setTraderType,
    setPrimaryMarket,
    setTradingModel,
    setStartedTrading,
  }

  function hydrateProfileRow(row: Record<string, unknown> | null | undefined) {
    if (!row) return
    applySettingsFormSeed(buildSettingsFormSeed(row), formSetters)
    setProfile(row)
  }

  useLayoutEffect(() => {
    if (!user?.id || formSeededRef.current) return
    const cached = readSettingsProfileCache(user.id)
    const merged = mergeSettingsProfileSources(cached, sharedProfile)
    const seedRow =
      merged ??
      (sharedProfile ? sharedSliceToSettingsRow(sharedProfile) : null)
    if (seedRow) {
      hydrateProfileRow(seedRow)
      formSeededRef.current = true
    }
  }, [user?.id, sharedProfile])

  useEffect(() => {
    if (profileLoading) return
    if (!user?.id) {
      router.push("/login")
      return
    }

    let cancelled = false

    void (async () => {
      const cached = readSettingsProfileCache(user.id)
      if (cached) {
        if (!formSeededRef.current) {
          hydrateProfileRow(cached)
          formSeededRef.current = true
        } else {
          setProfile(cached)
        }
        setSharedProfile((prev) => settingsSaveToSharedSlice(cached, prev))
        return
      }

      const data = await fetchSettingsProfileRow(supabase, user.id)
      if (cancelled || !data) return

      if (!formSeededRef.current) {
        hydrateProfileRow(data)
        formSeededRef.current = true
      } else {
        setProfile(data)
      }
      setSharedProfile((prev) => settingsSaveToSharedSlice(data, prev))
    })()

    return () => {
      cancelled = true
    }
  }, [user?.id, profileLoading, router, setSharedProfile])

  useEffect(() => {
    if (activeTab !== "affiliate" || profileLoading || !user?.id) return

    void Promise.all([
      refreshAffiliateState(user.id),
      refreshAffiliateConnect(user.id),
    ]).catch((e) => {
      console.error("Affiliate state refresh failed:", e)
    })
  }, [activeTab, user?.id, profileLoading])

  useEffect(() => {
    if (typeof window === "undefined") return
    const params = new URLSearchParams(window.location.search)
    if (params.get("checkout") !== "success") return
    if (!user?.id) return
    void fetchProfile(user.id, { force: true })
  }, [user?.id])

  useEffect(() => {
    if (typeof window === "undefined") return

    function syncTabFromHash() {
      const tab = resolveSettingsTabFromHash(window.location.hash)
      setActiveTab(tab ?? "account")
    }

    syncTabFromHash()
    window.addEventListener("hashchange", syncTabFromHash)
    return () => window.removeEventListener("hashchange", syncTabFromHash)
  }, [])

  async function fetchProfile(userId: string, options?: { force?: boolean }) {
    const data = await fetchSettingsProfileRow(supabase, userId, options)

    if (data) {
      hydrateProfileRow(data)
    }

    return data
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
    if (!user || savingProfileRef.current || savingProfile) return

    if (invalidStartedTradingDate) {
      showPopup(feedbackPresets.invalidStartedTradingDate())
      return
    }

    savingProfileRef.current = true
    setSavingProfile(true)

    try {

    let avatarUrl = avatarPreview
    if (avatarFile) {
      const uploaded = await uploadAvatar()
      if (uploaded) avatarUrl = uploaded
    }

    const cleanUsername = normalizeProfileUsername(username)
    const emptyUsernameError = validateProfileUsernameNotEmpty(cleanUsername)
    if (emptyUsernameError) {
      showPopup({ type: "error", message: emptyUsernameError })
      return
    }

    const currentUsername = normalizeProfileUsername(
      String(profile?.username ?? "")
    )
    const usernameChanged = !profileUsernamesEqual(
      currentUsername,
      cleanUsername
    )
    const changeCount = Number(profile?.username_change_count ?? 0)

    if (usernameChanged && !canChangeProfileUsername(changeCount)) {
      showPopup({
        type: "error",
        message: "Maximum username changes reached.",
      })
      return
    }

    if (usernameChanged) {
      const { data: existingUser, error: usernameLookupErr } = await supabase
        .from("profiles")
        .select("id")
        .eq("username", cleanUsername)
        .neq("id", user.id)
        .maybeSingle()

      if (usernameLookupErr) {
        showPopup({ type: "error", message: "Something went wrong" })
        return
      }

      if (existingUser) {
        showPopup({ type: "error", message: "Username already in use" })
        return
      }
    }

    const updatePayload: Record<string, unknown> = {
      name: name.trim() || null,
      is_private: isPrivate,
      bio,
      avatar_url: avatarUrl,
      trading_style: tradingStyle,
      trader_type: traderType.trim() || null,
      primary_market: primaryMarket.trim() || null,
      trading_model: tradingModel || tradingStyle || null,
      started_trading: startedTrading.trim() || null,
    }

    if (usernameChanged) {
      updatePayload.username = cleanUsername
      updatePayload.username_change_count = changeCount + 1
    } else if (cleanUsername !== String(profile?.username ?? "")) {
      updatePayload.username = cleanUsername
    }

    const { error } = await supabase
      .from("profiles")
      .update(updatePayload)
      .eq("id", user.id)

    if (error) {
      if (error.code === "23505" && isProfilesUsernameConflict(error)) {
        showPopup({ type: "error", message: "Username already in use" })
      } else {
        showPopup({ type: "error", message: "Something went wrong" })
      }
      return
    }

    const nextChangeCount = usernameChanged ? changeCount + 1 : changeCount

    if (usernameChanged) {
      const { error: mirrorErr } = await mirrorAccountSettingsUsernameChangeCount(
        supabase,
        user.id,
        nextChangeCount
      )
      if (mirrorErr) {
        console.error("mirror account_settings.username_change_count:", mirrorErr)
      }
    }

    const nextProfile: Record<string, unknown> = {
      ...(profile ?? {}),
      name: name.trim() || null,
      is_private: isPrivate,
      username: cleanUsername,
      username_change_count: nextChangeCount,
      bio,
      avatar_url: avatarUrl,
      trading_style: tradingStyle,
      trader_type: traderType.trim() || null,
      primary_market: primaryMarket.trim() || null,
      trading_model: tradingModel || tradingStyle || null,
      started_trading: startedTrading.trim() || null,
    }

    setUsername(cleanUsername)
    setProfile(nextProfile)
    setAvatarFile(null)
    persistSettingsProfileEverywhere(user.id, nextProfile)
    setSharedProfile((prev) => settingsSaveToSharedSlice(nextProfile, prev))
    showPopup(feedbackPresets.profileSaveSuccess())
    } finally {
      savingProfileRef.current = false
      setSavingProfile(false)
    }
  }

  async function sendCreatePasswordEmail() {
    if (!user?.email || savingPassword) return

    setSavingPassword(true)
    const { error } = await supabase.auth.resetPasswordForEmail(user.email, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    setSavingPassword(false)

    if (error) {
      showPopup({
        type: "error",
        message: "Something went wrong. Please try again.",
      })
      return
    }

    showPopup({
      type: "success",
      message: "Check your email for a link to set your password.",
    })
  }

  async function updatePassword() {
    if (!user) return

    const trimmedNew = newPassword.trim()
    const trimmedConfirm = confirmPassword.trim()

    if (!trimmedNew) {
      showPopup({ type: "error", message: "Please enter a new password." })
      return
    }
    if (!trimmedConfirm) {
      showPopup({ type: "error", message: "Please confirm your new password." })
      return
    }
    if (newPassword.length < 6) {
      showPopup({
        type: "error",
        message: "Password must be at least 6 characters long.",
      })
      return
    }
    if (newPassword !== confirmPassword) {
      showPopup({ type: "error", message: "Passwords do not match." })
      return
    }

    setSavingPassword(true)
    const { error } = await supabase.auth.updateUser({
      password: newPassword,
    })
    setSavingPassword(false)

    if (error) {
      showPopup({
        type: "error",
        message: "Something went wrong. Please try again.",
      })
      return
    }

    setNewPassword("")
    setConfirmPassword("")
    showPopup({ type: "success", message: "Password updated successfully" })
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
      showPopup(
        persistentError("Delete Failed", "Failed to delete account.")
      )
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
      showPopup(
        persistentError("Export Failed", "Failed to export data.")
      )
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
        showPopup({ type: "warning", message: "You already have a Trade Room" })
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
        showPopup({ type: "success", message: "Trade Room created!" })
        return
      }

      router.push(
        `/trade-rooms?room=${encodeURIComponent(slug)}&setup=true`
      )
    } catch (err) {
      console.error(err)
      showPopup({ type: "error", message: "Failed to create room" })
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
          showPopup({ type: "error", message: "Something went wrong" })
          router.push("/login?next=checkout")
          return
        }
        showPopup({ type: "error", message: "Something went wrong" })
        return
      }

      if (data.url) {
        window.location.href = data.url as string
      } else {
        showPopup({ type: "error", message: "Something went wrong" })
      }
    } catch (e) {
      console.error(e)
      showPopup({ type: "error", message: "Something went wrong" })
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
        showPopup({ type: "error", message: "Something went wrong" })
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
          showPopup({ type: "error", message: "Something went wrong" })
          router.push("/login")
          return
        }
        showPopup({ type: "error", message: "Something went wrong" })
        return
      }

      if (data.url) {
        window.location.href = data.url as string
      } else {
        showPopup({ type: "error", message: "Something went wrong" })
      }
    } catch (e) {
      console.error(e)
      showPopup({ type: "error", message: "Something went wrong" })
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
  const usernameChangeCount = Number(profile?.username_change_count ?? 0)
  const remainingUsernameChanges = usernameChangesRemaining(usernameChangeCount)
  const atUsernameChangeLimit =
    usernameChangeCount >= MAX_PROFILE_USERNAME_CHANGES
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
      showPopup({ type: "success", message: "Copied!" })
    } catch (err) {
      console.error("Copy failed", err)
      showPopup({ type: "error", message: "Something went wrong" })
    }
  }

  async function afterAffiliateModalSubmit() {
    if (!user) return
    setShowAffiliateModal(false)
    await Promise.all([
      fetchProfile(user.id, { force: true }),
      refreshAffiliateState(user.id),
      refreshAffiliateConnect(user.id),
    ])
  }

  const cachedSettingsProfile = user?.id
    ? readSettingsProfileCache(user.id)
    : null
  const hasInstantProfile = Boolean(
    user?.id && (sharedProfile || cachedSettingsProfile || profile)
  )
  const showFullSkeleton = profileLoading && !hasInstantProfile

  if (showFullSkeleton) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-6 text-white">
          <SkeletonSettingsPage />
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
                <div>
                  <span
                    id="settings-avatar-label"
                    className="mb-2 block text-sm text-gray-400"
                  >
                    Profile picture
                  </span>
                  <div
                    className="flex flex-wrap items-center gap-4"
                    aria-labelledby="settings-avatar-label"
                  >
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
                      id="settings-avatar"
                      type="file"
                      accept="image/*"
                      aria-labelledby="settings-avatar-label"
                      onChange={(e) => {
                        const file = e.target.files?.[0]
                        if (!file) return
                        setAvatarFile(file)
                        setAvatarPreview(URL.createObjectURL(file))
                      }}
                      className="max-w-full text-sm text-gray-300 file:mr-2 file:rounded-lg file:border-0 file:bg-white/10 file:px-3 file:py-2 file:text-sm file:text-gray-100 hover:file:bg-white/20"
                    />
                  </div>
                </div>

                <div>
                  <label
                    htmlFor="settings-display-name"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Display name
                  </label>
                  <input
                    id="settings-display-name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="How your name appears on TradeTraxs"
                    className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                </div>

                <div>
                  <label
                    htmlFor="settings-username"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Username
                  </label>
                  <input
                    id="settings-username"
                    value={username}
                    onChange={(e) =>
                      setUsername(sanitizeUsernameInputForTyping(e.target.value))
                    }
                    placeholder="username"
                    autoComplete="username"
                    disabled={atUsernameChangeLimit}
                    className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500 disabled:cursor-not-allowed disabled:opacity-50"
                  />
                  <p className="mt-2 text-xs text-gray-400">
                    You may change your username up to 2 times.
                  </p>
                  {atUsernameChangeLimit ? (
                    <p className="mt-1 text-xs text-amber-400/90">
                      Maximum username changes reached.
                    </p>
                  ) : (
                    <p className="mt-1 text-xs text-gray-400">
                      Remaining changes: {remainingUsernameChanges}
                    </p>
                  )}
                </div>

                <div
                  className="flex flex-col gap-3 rounded-xl border border-white/10 bg-black/20 p-4 sm:flex-row sm:items-center sm:justify-between"
                  aria-labelledby="settings-private-profile-label"
                >
                  <div>
                    <p
                      id="settings-private-profile-label"
                      className="font-medium text-white"
                    >
                      Private profile
                    </p>
                    <p className="text-xs text-gray-400">
                      Only followers can view your full profile
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setIsPrivate(!isPrivate)}
                    aria-pressed={isPrivate}
                    className={`shrink-0 rounded-lg px-4 py-2 text-sm font-medium transition ${
                      isPrivate
                        ? "bg-emerald-500 text-white"
                        : "bg-white/10 text-white"
                    }`}
                  >
                    {isPrivate ? "On" : "Off"}
                  </button>
                </div>

                <div>
                  <label htmlFor="settings-bio" className="mb-1 block text-sm text-gray-400">
                    Bio
                  </label>
                  <textarea
                    ref={bioTextareaRef}
                    id="settings-bio"
                    value={bio}
                    onChange={(e) => setBio(e.target.value)}
                    placeholder="Tell others about your trading"
                    rows={3}
                    className="w-full resize-none overflow-hidden rounded-xl border border-white/10 bg-black/30 p-3 leading-normal placeholder:text-gray-500"
                  />
                </div>

                <div>
                  <label
                    htmlFor="settings-trading-style"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Trading style
                  </label>
                  <input
                    id="settings-trading-style"
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
                  <label
                    htmlFor="settings-trader-type"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Trader Type
                  </label>
                  <select
                    id="settings-trader-type"
                    value={traderType}
                    onChange={(e) =>
                      setTraderType(normalizeTraderType(e.target.value))
                    }
                    className="w-full rounded-xl border border-white/10 bg-black/30 p-3 text-white"
                  >
                    <option value="">Select trader type (optional)</option>
                    {TRADER_TYPE_OPTIONS.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label
                    htmlFor="settings-primary-market"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Primary market
                  </label>
                  <input
                    id="settings-primary-market"
                    value={primaryMarket}
                    onChange={(e) => setPrimaryMarket(e.target.value)}
                    placeholder="e.g. NQ, ES, Gold, BTC, EUR/USD"
                    className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                  />
                </div>

                <div>
                  <label
                    htmlFor="settings-started-trading"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Started trading date
                  </label>
                  <NativeDateInput
                    id="settings-started-trading"
                    max={localTodayDate}
                    value={startedTrading}
                    onChange={(e) => handleStartedTradingChange(e.target.value)}
                  />
                </div>

                <button
                  type="button"
                  onClick={() => void saveProfileTab()}
                  disabled={savingProfile || invalidStartedTradingDate}
                  className="w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 py-3 font-semibold disabled:opacity-50"
                >
                  {savingProfile ? "Saving…" : "Save Profile"}
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
                    <label htmlFor="settings-email" className="text-xs text-gray-500">
                      Email
                    </label>
                    <p
                      id="settings-email"
                      className="mt-1 break-all rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-white"
                    >
                      {user?.email ?? "—"}
                    </p>
                  </div>
                </section>

                <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                    {isCreatePasswordFlow ? "Set password" : "Change password"}
                  </h3>
                  <p className="mt-1 text-sm text-gray-400">
                    {isCreatePasswordFlow
                      ? "Create a password so you can also sign in using your email and password, in addition to Google."
                      : "Choose a strong password you have not used elsewhere"}
                  </p>
                  {isCreatePasswordFlow ? (
                    <button
                      type="button"
                      onClick={() => void sendCreatePasswordEmail()}
                      disabled={savingPassword || !user?.email}
                      className="mt-4 w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 py-3 font-semibold disabled:opacity-50"
                    >
                      {savingPassword ? "Sending…" : "Set password"}
                    </button>
                  ) : (
                    <>
                      <div className="mt-4">
                        <label
                          htmlFor="settings-new-password"
                          className="mb-1 block text-sm text-gray-400"
                        >
                          New password
                        </label>
                        <AuthPasswordInput
                          id="settings-new-password"
                          autoComplete="new-password"
                          value={newPassword}
                          onChange={(e) => setNewPassword(e.target.value)}
                          placeholder="Enter new password"
                          className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                        />
                      </div>
                      <div className="mt-4">
                        <label
                          htmlFor="settings-confirm-password"
                          className="mb-1 block text-sm text-gray-400"
                        >
                          Confirm password
                        </label>
                        <AuthPasswordInput
                          id="settings-confirm-password"
                          autoComplete="new-password"
                          value={confirmPassword}
                          onChange={(e) => setConfirmPassword(e.target.value)}
                          placeholder="Confirm new password"
                          className="w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-500"
                        />
                      </div>
                      <button
                        type="button"
                        onClick={() => void updatePassword()}
                        disabled={savingPassword}
                        className="mt-4 w-full rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 py-3 font-semibold disabled:opacity-50"
                      >
                        {savingPassword ? "Updating…" : "Update password"}
                      </button>
                    </>
                  )}
                </section>

                <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                    Data & account
                  </h3>
                  <p className="mt-1 text-sm text-gray-400">
                    Export your data or permanently delete your account
                  </p>
                  <div className="mt-4 flex flex-wrap gap-3">
                    <button
                      type="button"
                      onClick={() => void handleExportData()}
                      className="rounded-lg bg-blue-500/10 px-4 py-2 text-blue-400 hover:bg-blue-500/20"
                    >
                      Export My Data (CSV)
                    </button>
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
                  </div>
                </section>

                <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                  <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
                    Legal
                  </h3>
                  <p className="mt-1 text-sm text-gray-400">
                    Review our policies and terms of use
                  </p>
                  <ul className="mt-4 space-y-2 text-sm">
                    <li>
                      <a
                        href="/privacy"
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-blue-300 underline hover:text-blue-200"
                      >
                        Privacy Policy
                      </a>
                    </li>
                    <li>
                      <a
                        href="/terms"
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-blue-300 underline hover:text-blue-200"
                      >
                        Terms of Service
                      </a>
                    </li>
                  </ul>
                </section>
              </div>
            )}

            {activeTab === "trading-accounts" && (
              <TradingAccountsSettingsSection
                userId={user?.id}
                isPro={isProActive(profile)}
              />
            )}

            {activeTab === "subscription" && (
              <div className="space-y-6 rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
                <div className="space-y-4">
                  <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                    <p className="text-xs text-gray-500">Plan name</p>
                    <p className="mt-1 font-semibold text-white">
                      {isProActive(profile)
                        ? `${TRAXPRO_PLAN_NAME} (${TRAXPRO_PRICE_DISPLAY} ${TRAXPRO_BILLING_LABEL.toLowerCase()})`
                        : "Free Plan"}
                    </p>
                  </div>

                  <div className="rounded-xl border border-white/10 bg-black/20 p-4 space-y-3">
                    <div>
                      <p className="text-xs text-gray-500">Status</p>
                      <p className="mt-1 text-sm text-gray-400">
                        Billing: {isProActive(profile) ? "Pro" : "Free"}
                      </p>
                      <p className="mt-1 text-sm text-gray-400">
                        Membership: {getMembershipStatus(profile)}
                      </p>
                    </div>

                    {shouldShowTrialInfo(profile) ? (
                      <div className="border-t border-white/10 pt-3">
                        <p className="text-xs text-gray-500">Trial Ends</p>
                        <p className="mt-1 text-sm font-medium text-amber-200">
                          {formatSubscriptionDateTime(profile?.trial_end)}
                        </p>
                      </div>
                    ) : null}

                    {shouldShowRenewsOn(profile) ? (
                      <div className="border-t border-white/10 pt-3">
                        <p className="text-xs text-gray-500">Renews On</p>
                        <p className="mt-1 text-sm font-medium text-emerald-200">
                          {formatSubscriptionDateTime(profile?.current_period_end)}
                        </p>
                      </div>
                    ) : null}

                    {shouldShowScheduledCancellation(profile) ? (
                      <div className="border-t border-white/10 pt-3">
                        <p className="text-xs text-gray-500">Cancellation Scheduled</p>
                        <p className="mt-1 text-sm font-medium text-red-200">
                          {formatScheduledCancellation(profile)}
                        </p>
                      </div>
                    ) : null}
                  </div>
                </div>

                <div className="rounded-xl border border-white/10 bg-black/20 p-4">
                  <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                    Feature access
                  </p>
                  <ul className="mt-3 space-y-2">
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>Basic Dashboard Analytics</span>
                      <span aria-hidden>✅</span>
                    </li>
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>Advanced Dashboard Insights</span>
                      <span aria-hidden>
                        {isProActive(profile) ? "✅" : "❌"}
                      </span>
                    </li>
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>AI Analyst</span>
                      <span aria-hidden>
                        {isProActive(profile) ? "✅" : "❌"}
                      </span>
                    </li>
                    <li className="flex items-center justify-between gap-4 text-sm text-gray-200">
                      <span>Unlimited Accounts</span>
                      <span aria-hidden>
                        {isProActive(profile) ? "✅" : "❌"}
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
      <FeedbackModal {...feedbackModalProps} />
    </>
  )
}
