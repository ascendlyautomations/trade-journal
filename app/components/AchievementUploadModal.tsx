"use client"

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { compressContentImage, CONTENT_IMAGE_CROP_PRESET, CONTENT_IMAGE_DISPLAY_PRESET } from "@/lib/contentImagePipeline"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import { validateImageUpload } from "@/lib/uploadValidation"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  normalizeAchievementDateInputValue,
  resolveNewAchievementDateInputValue,
} from "@/lib/achievementDate"
import {
  ACHIEVEMENT_TYPE,
  ACHIEVEMENT_TYPE_OPTIONS,
  type Achievement,
  badgeKeyFromType,
  canonicalAchievementType,
  categoryFromType,
  isPayoutAchievementType,
  normalizeAchievementMetadata,
} from "@/lib/achievements"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import Modal from "@/app/components/ui/Modal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { persistentError } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import type { Json, TableInsert, TableUpdate } from "@/lib/supabaseTypes"
import {
  buildAchievementValidationPopup,
  validateAchievementForm,
} from "@/lib/validateAchievementForm"
import {
  buildAchievementAccountSnapshot,
  findTradeAccountById,
  shouldOpenPassedEvalContinuance,
  shouldRunPropFirmPayoutWorkflow,
  tradeAccountToPropFirmMilestoneAccount,
} from "@/lib/achievementAccountLink"
import { fetchPropFirmPayoutSetupContext } from "@/lib/fetchPropFirmPayoutSetupContext"
import { useAchievementPropFirmEvalContinuance } from "@/app/components/achievement/AchievementPropFirmEvalContinuanceHost"
import TradeAccountPicker, {
  type TradeAccountOption,
} from "@/app/components/TradeAccountPicker"
import CustomSelect from "@/app/components/CustomSelect"
import CreateAccountModal from "@/app/components/CreateAccountModal"
import PayoutSetupModal, {
  type PayoutSetupValues,
} from "@/app/components/PayoutSetupModal"
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { isProActive } from "@/lib/subscription"
import { assertCanCreateTradingAccount } from "@/lib/tradingAccounts"
import { assertRequiredAccountValue } from "@/lib/createAccountForm"
import { upsertAccountInCache } from "@/lib/appDataCache"
import { supabaseMutationFeedback } from "@/lib/supabaseMutationFeedback"
import { computePayoutDrawdownFloor } from "@/lib/propfirmMetrics"
import {
  recordAccountPayout,
  type AccountPayoutCycle,
  type PendingPropFirmPayoutRecord,
  type RecordAccountPayoutResult,
} from "@/lib/propfirmPayoutCycles"

export type AchievementFormState = {
  achievement_type: string
  title: string
  description: string
  payout_amount: string
  achieved_at: string
  image_url: string | null
  is_public: boolean
  is_featured: boolean
  firm?: string
  account_name?: string
  account_size?: string
  account_id?: string
  metadata?: Record<string, unknown> | null
}

export const EMPTY_ACHIEVEMENT_FORM: AchievementFormState = {
  achievement_type: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT,
  title: "",
  description: "",
  payout_amount: "",
  achieved_at: "",
  image_url: null,
  is_public: true,
  is_featured: false,
}

export type AchievementUploadInitialValues = Partial<AchievementFormState>

export type AchievementUploadModalProps = {
  open: boolean
  onClose: () => void
  userId: string | null
  onSaved?: () => void | Promise<void>
  initialValues?: AchievementUploadInitialValues
  lockAchievementType?: boolean
  editingAchievement?: Achievement | null
  dialogTitle?: string
  dialogSubtitle?: string
  saveLabel?: string
  /**
   * When true, skip in-modal prop firm payout setup/recording (legacy).
   * Prefer `pendingPropFirmPayout` when the parent collected payout details
   * but has not written them yet.
   */
  propFirmPayoutAlreadyRecorded?: boolean
  /**
   * Payout details collected by the parent (e.g. Prop Firm Mode) that must
   * only be recorded after the achievement is created successfully.
   */
  pendingPropFirmPayout?: PendingPropFirmPayoutRecord | null
  /** Called after a pending/in-modal payout is recorded successfully. */
  onPropFirmPayoutRecorded?: (payload: {
    cycle: AccountPayoutCycle
    accountPreferences: RecordAccountPayoutResult["accountPreferences"]
    pending: PendingPropFirmPayoutRecord
  }) => void | Promise<void>
  /**
   * Soft-close when the upload overlay takes over. Must hide the compose UI
   * without abandoning in-flight payout/achievement work.
   */
  onComposeDismissed?: () => void
  /**
   * When true, skip in-modal Passed Eval continuance so the parent
   * (e.g. Prop Firm Mode) can open its own flow with the full account.
   */
  deferPassedEvalContinuance?: boolean
}

AchievementUploadModal.displayName = "AchievementUploadModal"

function mergeInitialForm(
  initialValues?: AchievementUploadInitialValues
): AchievementFormState {
  return {
    ...EMPTY_ACHIEVEMENT_FORM,
    ...initialValues,
    achievement_type:
      initialValues?.achievement_type ?? EMPTY_ACHIEVEMENT_FORM.achievement_type,
  }
}

export default function AchievementUploadModal({
  open,
  onClose,
  userId,
  onSaved,
  initialValues,
  lockAchievementType = false,
  editingAchievement = null,
  dialogTitle,
  dialogSubtitle,
  saveLabel,
  propFirmPayoutAlreadyRecorded = false,
  pendingPropFirmPayout = null,
  onPropFirmPayoutRecorded,
  onComposeDismissed,
  deferPassedEvalContinuance = false,
}: AchievementUploadModalProps) {
  const editingId = editingAchievement?.id ?? null
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState<AchievementFormState>(EMPTY_ACHIEVEMENT_FORM)
  const [file, setFile] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [removeImage, setRemoveImage] = useState(false)
  const imageCrop = useImageCropUpload({
    preset: CONTENT_IMAGE_CROP_PRESET,
    onCropped: (cropped) => {
      setRemoveImage(false)
      setFile(cropped)
    },
    onValidationError: (message) => {
      showPopup(persistentError("Invalid Image", message))
    },
  })
  const fileInputRef = imageCrop.fileInputRef
  const uploadingRef = useRef(false)
  const { runUpload } = useUploadProgress()
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [accounts, setAccounts] = useState<TradeAccountOption[]>([])
  const [selectedAccount, setSelectedAccount] =
    useState<TradeAccountOption | null>(null)
  const [showCreateAccountModal, setShowCreateAccountModal] = useState(false)
  const [creatingAccount, setCreatingAccount] = useState(false)
  const creatingAccountRef = useRef(false)
  const [planProfile, setPlanProfile] = useState<{
    is_pro?: boolean | null
    subscription_status?: string | null
  } | null>(null)
  const [payoutConfirmOpen, setPayoutConfirmOpen] = useState(false)
  const [payoutSetupOpen, setPayoutSetupOpen] = useState(false)
  const [payoutSetupKey, setPayoutSetupKey] = useState(0)
  const [recordingPayout, setRecordingPayout] = useState(false)
  const [payoutSetupContext, setPayoutSetupContext] = useState<Awaited<
    ReturnType<typeof fetchPropFirmPayoutSetupContext>
  >["context"]>(null)
  const pendingAchievementSaveRef = useRef(false)
  /** In-modal payout setup values — recorded only after achievement insert succeeds. */
  const pendingPayoutFromSetupRef = useRef<PendingPropFirmPayoutRecord | null>(
    null
  )

  const {
    openPassedEvalContinuance,
    evalContinuanceModals,
    evalContinuanceBusy,
  } = useAchievementPropFirmEvalContinuance({
    supabase,
    userId,
  })

  const isPro = isProActive(planProfile)

  const loadAccounts = useCallback(async (uid: string) => {
    const { data, error: fetchErr } = await supabase
      .from("accounts")
      .select("*")
      .eq("user_id", uid)

    if (fetchErr) {
      console.error("[AchievementUploadModal] accounts fetch:", fetchErr)
      setAccounts([])
      return
    }

    const rows = (data ?? [])
      .filter((acc) => acc.is_active !== false)
      .map((acc) => ({
        name: String(acc.name ?? ""),
        size: String(acc.account_size ?? ""),
        id: String(acc.id),
        account_number: acc.account_number ?? null,
        mode: acc.mode ?? "live",
        category: acc.category ?? null,
        consistency: acc.consistency ?? null,
        max_drawdown: acc.max_drawdown ?? null,
        daily_drawdown: acc.daily_drawdown ?? null,
        profit_target: acc.profit_target ?? null,
        winning_days: acc.winning_days ?? null,
        winning_day_threshold: acc.winning_day_threshold ?? null,
      }))

    setAccounts(rows)
  }, [])

  const loadPlanProfile = useCallback(async (uid: string) => {
    const { data } = await supabase
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", uid)
      .maybeSingle()
    setPlanProfile(data ?? null)
  }, [])

  const syncSelectedAccountToForm = useCallback(
    (account: TradeAccountOption | null) => {
      setSelectedAccount(account)
      if (!account) {
        setForm((prev) => ({
          ...prev,
          account_id: undefined,
          account_name: undefined,
          account_size: undefined,
          firm: undefined,
        }))
        return
      }

      const snapshot = buildAchievementAccountSnapshot(account)
      setForm((prev) => ({
        ...prev,
        account_id: snapshot.account_id,
        account_name: snapshot.account_name,
        account_size: snapshot.account_size,
        firm: snapshot.firm ?? undefined,
      }))
    },
    []
  )

  const resetForm = useCallback(() => {
    let nextSelectedAccount: TradeAccountOption | null = null

    if (editingAchievement) {
      const savedDate = normalizeAchievementDateInputValue(
        editingAchievement.achieved_at
      )
      setForm({
        achievement_type: canonicalAchievementType(
          editingAchievement.achievement_type
        ),
        title: editingAchievement.title || "",
        description: editingAchievement.description || "",
        payout_amount:
          editingAchievement.value_numeric != null &&
          Number.isFinite(Number(editingAchievement.value_numeric))
            ? String(editingAchievement.value_numeric)
            : "",
        achieved_at: savedDate,
        image_url: editingAchievement.image_url || null,
        is_public: !!editingAchievement.is_public,
        is_featured: !!editingAchievement.is_featured,
        firm: editingAchievement.firm ?? undefined,
        account_name: editingAchievement.account_name ?? undefined,
        account_size: editingAchievement.account_size ?? undefined,
        account_id: editingAchievement.account_id ?? undefined,
        metadata: editingAchievement.metadata ?? null,
      })
      nextSelectedAccount = findTradeAccountById(
        accounts,
        editingAchievement.account_id
      )
    } else {
      const defaultDate = resolveNewAchievementDateInputValue(initialValues)
      const merged = mergeInitialForm({
        ...initialValues,
        achieved_at: defaultDate,
      })
      setForm(merged)
      nextSelectedAccount = findTradeAccountById(
        accounts,
        initialValues?.account_id
      )
    }

    setSelectedAccount(nextSelectedAccount)
    setFile(null)
    setPreviewUrl(null)
    setRemoveImage(false)
    setError(null)
    setPayoutConfirmOpen(false)
    setPayoutSetupOpen(false)
    pendingAchievementSaveRef.current = false
    pendingPayoutFromSetupRef.current = null
  }, [accounts, editingAchievement, initialValues])

  useLayoutEffect(() => {
    if (!open) return
    resetForm()
  }, [open, resetForm])

  useEffect(() => {
    if (!open || !userId) return
    void loadAccounts(userId)
    void loadPlanProfile(userId)
  }, [open, userId, loadAccounts, loadPlanProfile])

  useEffect(() => {
    if (!open) return
    if (editingAchievement?.account_id) {
      setSelectedAccount(
        findTradeAccountById(accounts, editingAchievement.account_id)
      )
      return
    }
    if (initialValues?.account_id) {
      setSelectedAccount(findTradeAccountById(accounts, initialValues.account_id))
    }
  }, [accounts, editingAchievement?.account_id, initialValues?.account_id, open])

  useEffect(() => {
    if (!file) {
      setPreviewUrl(null)
      return
    }
    const nextPreviewUrl = URL.createObjectURL(file)
    setPreviewUrl(nextPreviewUrl)
    return () => URL.revokeObjectURL(nextPreviewUrl)
  }, [file])

  function handleClose() {
    if (
      busy ||
      uploadingRef.current ||
      imageCrop.cropSourceFile ||
      recordingPayout ||
      evalContinuanceBusy
    ) {
      return
    }
    onClose()
  }

  const cropModalOpen = imageCrop.cropSourceFile != null

  async function handleCreateAccountSave(newAccount: {
    name: string
    size: string
    id: string
    category: string
    mode: string | null
    rules: unknown
  }) {
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }
    if (creatingAccountRef.current || creatingAccount || !userId) return

    creatingAccountRef.current = true
    setCreatingAccount(true)

    try {
      const gate = await assertCanCreateTradingAccount(supabase, userId, planProfile)
      if (!gate.ok) {
        showPopup(persistentError("Account Limit Reached", gate.message))
        return
      }

      const sizeGate = assertRequiredAccountValue(newAccount.size)
      if (!sizeGate.ok) {
        showPopup(persistentError("Account Value Required", sizeGate.message))
        return
      }

      const { data, error: insertErr } = await supabase
        .from("accounts")
        .insert([
          {
            user_id: userId,
            name: newAccount.name,
            account_size: sizeGate.value,
            account_number: newAccount.id,
            category: newAccount.category,
            mode: newAccount.mode,
            is_active: true,
            can_add_trades: true,
          },
        ])
        .select()
        .single()

      if (insertErr) {
        console.error(insertErr)
        showPopup(supabaseMutationFeedback(insertErr, "Save Failed"))
        return
      }

      if (!data) return

      upsertAccountInCache(userId, data)

      const createdAccount: TradeAccountOption = {
        name: data.name,
        size: data.account_size ?? "",
        id: String(data.id),
        account_number: data.account_number ?? null,
        mode: data.mode,
        category: data.category,
      }

      setAccounts((prev) => [...prev, createdAccount])
      syncSelectedAccountToForm(createdAccount)
      setShowCreateAccountModal(false)
    } finally {
      creatingAccountRef.current = false
      setCreatingAccount(false)
    }
  }

  async function executeAchievementSave(options?: {
    payoutToRecord?: PendingPropFirmPayoutRecord | null
  }) {
    if (!userId) return

    setError(null)
    uploadingRef.current = true

    const achievementType = canonicalAchievementType(form.achievement_type)
    const payoutAmount = isPayoutAchievementType(achievementType)
      ? Number(String(form.payout_amount).replace(/,/g, ""))
      : null
    const accountSnapshot = selectedAccount
      ? buildAchievementAccountSnapshot(selectedAccount)
      : null

    const snapshotForm = { ...form }
    const snapshotFile = file
    const snapshotRemoveImage = removeImage
    const snapshotEditingId = editingId
    const snapshotSelectedAccount = selectedAccount
    const payoutToRecord =
      options?.payoutToRecord ??
      pendingPropFirmPayout ??
      pendingPayoutFromSetupRef.current

    try {
      await runUpload({
        title: snapshotFile
          ? snapshotEditingId
            ? "Updating Achievement"
            : "Uploading Achievement"
          : snapshotEditingId
            ? "Updating Achievement"
            : "Saving Achievement",
        onDismissCompose: onComposeDismissed ?? onClose,
        execute: async (report) => {
          let imageUrl = snapshotForm.image_url
          if (snapshotRemoveImage) {
            imageUrl = null
          }

          if (snapshotFile) {
            const validationError = validateImageUpload(snapshotFile)
            if (validationError) {
              throw new Error(validationError)
            }

            report({ percent: 10, stage: "Optimizing image…" })

            const ext = snapshotFile.name.includes(".")
              ? snapshotFile.name.split(".").pop()?.toLowerCase() || "jpg"
              : "bin"
            const safeBase = snapshotFile.name
              .replace(/\.[^/.]+$/, "")
              .toLowerCase()
              .replace(/[^a-z0-9-_]+/g, "-")
              .replace(/-+/g, "-")
              .replace(/^-|-$/g, "")
            let uploadFile: File = snapshotFile
            if (snapshotFile.type?.startsWith("image/")) {
              uploadFile = await compressContentImage(snapshotFile)
            }
            const uploadName = uploadFile.type?.startsWith("image/")
              ? uploadFile.name
              : `${safeBase || "image"}.${ext}`
            const filePath = `achievements/${userId}/${Date.now()}-${uploadName}`

            report({ percent: 18, stage: "Preparing upload…" })
            const stageReport = createMonotonicReporter(report, {
              min: 18,
              max: 72,
            })
            const { error: uploadErr } = await uploadToSupabaseStorageWithProgress(
              supabase,
              {
                bucket: "screenshots",
                path: filePath,
                file: uploadFile,
                upsert: true,
                onProgress: (loaded, total) => {
                  stageReport({
                    percent: mapUploadBytesToPercent(loaded, total, {
                      start: 20,
                      end: 72,
                    }),
                    stage: "Preparing upload…",
                  })
                },
              }
            )
            if (uploadErr) {
              throw new Error(uploadErr)
            }

            const { data: publicData } = supabase.storage
              .from("screenshots")
              .getPublicUrl(filePath)
            imageUrl = publicData.publicUrl
          } else {
            report({ percent: 40, stage: "Preparing achievement…" })
          }

          const payload = {
            user_id: userId,
            achievement_type: achievementType,
            title: snapshotForm.title.trim(),
            description: snapshotForm.description.trim() || null,
            badge_key: badgeKeyFromType(achievementType),
            category: categoryFromType(achievementType),
            tier: null,
            value_numeric: isPayoutAchievementType(achievementType)
              ? payoutAmount
              : null,
            value_text:
              isPayoutAchievementType(achievementType) && payoutAmount != null
                ? `+$${Math.abs(payoutAmount).toLocaleString(undefined, {
                    minimumFractionDigits: 0,
                    maximumFractionDigits: 2,
                  })}`
                : null,
            currency: isPayoutAchievementType(achievementType) ? "USD" : null,
            account_id: accountSnapshot?.account_id ?? snapshotForm.account_id ?? null,
            account_type: accountSnapshot?.account_type ?? null,
            account_name: accountSnapshot?.account_name ?? (snapshotForm.account_name?.trim() || null),
            account_size: accountSnapshot?.account_size ?? (snapshotForm.account_size?.trim() || null),
            mode: accountSnapshot?.mode ?? null,
            firm: accountSnapshot?.firm ?? (snapshotForm.firm?.trim() || null),
            achieved_at: snapshotForm.achieved_at || new Date().toISOString(),
            image_url: imageUrl,
            is_public: snapshotForm.is_public,
            is_featured: snapshotForm.is_featured,
            metadata: normalizeAchievementMetadata(
              snapshotForm.metadata
            ) as Json,
          }

          report({ percent: 82, stage: "Creating record…" })

          const { data: savedRow, error: saveErr } = snapshotEditingId
            ? await supabase
                .from("achievements")
                .update(payload satisfies TableUpdate<"achievements">)
                .eq("id", snapshotEditingId)
                .eq("user_id", userId)
                .select("id")
                .single()
            : await supabase
                .from("achievements")
                .insert(payload satisfies TableInsert<"achievements">)
                .select("id")
                .single()
          if (saveErr) {
            console.error("[achievements] save failed", saveErr)
            throw new Error(
              handleSupabaseError(saveErr, "Could not save achievement.")
            )
          }

          const savedAchievementId =
            savedRow?.id != null ? String(savedRow.id) : null

          if (payoutToRecord && !snapshotEditingId) {
            report({ percent: 90, stage: "Recording payout…" })
            const { cycle, accountPreferences, error: payoutError } =
              await recordAccountPayout(
                supabase,
                payoutToRecord.accountId,
                payoutToRecord.input,
                payoutToRecord.nextCycleNumber
              )

            if (payoutError || !cycle) {
              console.error(payoutError ?? "Failed to record payout")
              if (savedAchievementId) {
                const { error: rollbackErr } = await supabase
                  .from("achievements")
                  .delete()
                  .eq("id", savedAchievementId)
                  .eq("user_id", userId)
                if (rollbackErr) {
                  console.error(
                    "[achievements] payout rollback delete failed",
                    rollbackErr
                  )
                }
              }
              throw new Error(
                payoutError ||
                  "Could not record payout. Please try again."
              )
            }

            pendingPayoutFromSetupRef.current = null
            await onPropFirmPayoutRecorded?.({
              cycle,
              accountPreferences,
              pending: payoutToRecord,
            })
          }

          report({ percent: 95, stage: "Finishing…" })
          await onSaved?.()

          if (!snapshotEditingId) {
            void import("@/lib/nativeHaptics").then(({ hapticSuccess }) => {
              hapticSuccess("achievement-unlocked")
            })
          }

          if (
            !snapshotEditingId &&
            !deferPassedEvalContinuance &&
            shouldOpenPassedEvalContinuance(achievementType, snapshotSelectedAccount)
          ) {
            openPassedEvalContinuance(
              tradeAccountToPropFirmMilestoneAccount(snapshotSelectedAccount!)
            )
          }
        },
      })
    } catch {
      // Overlay handles retry/cancel.
    } finally {
      uploadingRef.current = false
      pendingAchievementSaveRef.current = false
    }
  }

  async function handlePayoutSetupSubmit(values: PayoutSetupValues) {
    if (!userId || !selectedAccount || !payoutSetupContext) return

    setRecordingPayout(true)
    try {
      const balanceBeforePayout = payoutSetupContext.balanceBeforePayout
      const drawdownFloorAfterPayout = computePayoutDrawdownFloor(
        values.drawdownBehavior,
        payoutSetupContext.startingBalance,
        payoutSetupContext.cycleTrailingMetrics,
        Number(payoutSetupContext.account.max_drawdown) || 0
      )
      const nextCycleNumber =
        payoutSetupContext.activePayoutCycle?.cycle_number != null
          ? payoutSetupContext.activePayoutCycle.cycle_number + 1
          : 1

      const pending: PendingPropFirmPayoutRecord = {
        accountId: selectedAccount.id,
        input: {
          balanceAfterPayout: values.balanceAfterPayout,
          payoutAmount: values.payoutAmount,
          drawdownBehavior: values.drawdownBehavior,
          drawdownFloorAfterPayout,
          balanceBeforePayout,
          rememberDrawdownBehavior: values.rememberDrawdownBehavior,
        },
        nextCycleNumber,
      }

      pendingPayoutFromSetupRef.current = pending
      setPayoutSetupOpen(false)
      setPayoutSetupContext(null)
      await executeAchievementSave({ payoutToRecord: pending })
    } finally {
      setRecordingPayout(false)
    }
  }

  async function beginPropFirmPayoutWorkflow() {
    if (!userId || !selectedAccount) return

    const { context, error } = await fetchPropFirmPayoutSetupContext(
      supabase,
      userId,
      selectedAccount.id
    )

    if (error || !context) {
      showPopup(
        persistentError(
          "Payout Setup Unavailable",
          error
            ? handleSupabaseError(error)
            : "Could not load account payout details."
        )
      )
      return
    }

    setPayoutSetupContext(context)
    setPayoutConfirmOpen(true)
  }

  async function saveAchievement() {
    if (isDemoModeActive()) {
      requestDemoSignup("upload")
      return
    }
    if (!userId) {
      showPopup(
        persistentError("Sign In Required", "Please log in to save your achievement.")
      )
      return
    }
    if (uploadingRef.current || recordingPayout) return

    const achievementType = canonicalAchievementType(form.achievement_type)
    const hasImage = file != null || (!!form.image_url && !removeImage)
    const validation = validateAchievementForm({
      achievement_type: achievementType,
      title: form.title,
      payout_amount: form.payout_amount,
      achieved_at: form.achieved_at,
      hasImage,
      accountId: selectedAccount?.id ?? form.account_id,
    })

    if (!validation.ok) {
      showPopup(buildAchievementValidationPopup(validation))
      return
    }

    if (
      shouldRunPropFirmPayoutWorkflow(achievementType, selectedAccount, {
        payoutAlreadyRecorded: propFirmPayoutAlreadyRecorded,
        hasPendingPayout: pendingPropFirmPayout != null,
      })
    ) {
      pendingAchievementSaveRef.current = true
      await beginPropFirmPayoutWorkflow()
      return
    }

    await executeAchievementSave()
  }

  if (!open) return null

  const heading = dialogTitle ?? (editingId ? "Edit Achievement" : "Add Achievement")
  const subheading =
    dialogSubtitle ??
    "Capture your achievements with a quick summary and image."
  const submitLabel =
    saveLabel ?? (editingId ? "Update Achievement" : "Save Achievement")

  return (
    <>
    <ScrollableModalShell
      open={open}
      onClose={handleClose}
      ariaLabel={heading}
      belowNavbar
      closeDisabled={busy}
      overlayClassName="z-[150] bg-black/75 backdrop-blur-md"
      backdropClassName="bg-transparent"
      panelClassName="max-w-3xl rounded-2xl border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] shadow-2xl shadow-blue-900/20"
      headerClassName="border-white/10 px-4 pb-3 pt-4 sm:px-6"
      bodyClassName="px-4 sm:px-6"
      footerClassName="border-white/10 px-4 py-4 sm:px-6"
      header={
        <>
          <h2 className="text-xl font-semibold tracking-tight text-white">{heading}</h2>
          <p className="mt-0.5 text-sm text-slate-300">{subheading}</p>
        </>
      }
      footer={
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            type="button"
            disabled={busy}
            onClick={handleClose}
            className="h-10 rounded-lg border border-white/20 bg-white/5 px-4 text-sm font-medium text-slate-200 transition hover:bg-white/10 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => void saveAchievement()}
            className="h-10 rounded-lg bg-blue-500 px-4 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500"
          >
            {submitLabel}
          </button>
        </div>
      }
    >
        {error ? (
          <div className="mb-4 rounded-lg border border-red-400/30 bg-red-500/10 p-3 text-sm text-red-200">
            {error}
          </div>
        ) : null}

        <div className="grid gap-2 sm:grid-cols-2 sm:gap-3">
          <label className="text-xs text-gray-300">
            Achievement Type
            <CustomSelect
              value={form.achievement_type}
              disabled={lockAchievementType}
              onChange={(val) =>
                setForm((prev) => ({ ...prev, achievement_type: val }))
              }
              className="mt-1.5"
              triggerClassName="flex h-11 w-full min-w-0 cursor-pointer items-center justify-between rounded-lg border border-white/15 bg-[#0a1329] px-3 text-left text-sm text-white outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
              options={ACHIEVEMENT_TYPE_OPTIONS.map((option) => ({
                label: option.label,
                value: option.value,
              }))}
            />
          </label>
          <label className="text-xs text-gray-300">
            Title
            <input
              type="text"
              value={form.title}
              onChange={(e) => setForm((prev) => ({ ...prev, title: e.target.value }))}
              placeholder="e.g. First payout from Apex"
              className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white placeholder:text-gray-400 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
            />
          </label>
          <label className="text-xs text-gray-300 sm:col-span-2">
            Trading Account
            <TradeAccountPicker
              className="mt-1.5"
              triggerId="achievement-account-trigger"
              accounts={accounts}
              isPro={isPro}
              selectedAccount={selectedAccount}
              onSelect={syncSelectedAccountToForm}
              onOpenCreate={() => setShowCreateAccountModal(true)}
              showExternalCreateButton={false}
            />
          </label>
          {isPayoutAchievementType(form.achievement_type) ? (
            <label className="text-xs text-gray-300">
              Payout Amount (USD)
              <input
                type="number"
                min="0"
                step="0.01"
                value={form.payout_amount}
                onChange={(e) =>
                  setForm((prev) => ({ ...prev, payout_amount: e.target.value }))
                }
                placeholder="3500"
                className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white placeholder:text-gray-400 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
              />
            </label>
          ) : null}
          <label className="text-xs text-gray-300">
            Achieved Date
            <NativeDateInput
              className="mt-1.5 rounded-lg border-white/15 bg-[#0a1329]"
              value={form.achieved_at}
              onChange={(e) =>
                setForm((prev) => ({ ...prev, achieved_at: e.target.value }))
              }
            />
          </label>
          <label className="text-xs text-gray-300">
            Upload Image
            <div className="mt-1.5 rounded-lg border border-white/15 bg-[#0a1329] p-2.5">
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={(e) => {
                  const selected = e.target.files?.[0] ?? null
                  if (!selected) return
                  imageCrop.handleFileSelected(selected)
                }}
                className="hidden"
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="h-9 rounded-md border border-blue-300/30 bg-blue-500/15 px-3 text-sm font-medium text-blue-100 transition hover:bg-blue-500/25"
              >
                {file ? "Change image" : "Choose image"}
              </button>
              <input
                type="text"
                readOnly
                value={file?.name || ""}
                placeholder="No image selected"
                className="mt-2 w-full rounded-md border border-white/10 bg-[#0b1220] px-2 py-1.5 text-xs text-slate-300"
              />
              {previewUrl ? (
                <TradeScreenshotImage
                  src={previewUrl}
                  preset={CONTENT_IMAGE_DISPLAY_PRESET}
                  alt="Selected preview"
                  className="mt-2 rounded-md border border-white/10"
                  logContext="achievement-upload-preview"
                />
              ) : form.image_url && !removeImage ? (
                <div className="mt-2 space-y-2">
                  <TradeScreenshotImage
                    src={form.image_url}
                    preset={CONTENT_IMAGE_DISPLAY_PRESET}
                    alt="Current achievement image"
                    className="rounded-md border border-white/10"
                    logContext="achievement-upload-existing"
                  />
                  <button
                    type="button"
                    onClick={() => setRemoveImage(true)}
                    className="rounded border border-red-400/40 px-2 py-0.5 text-[11px] text-red-300 hover:bg-red-500/10"
                  >
                    Delete image
                  </button>
                </div>
              ) : removeImage ? (
                <p className="mt-2 text-xs text-amber-300">
                  Image will be removed when you save.
                </p>
              ) : null}
            </div>
          </label>

          <label className="text-xs text-gray-300 sm:col-span-2">
            Description
            <textarea
              rows={4}
              value={form.description}
              onChange={(e) =>
                setForm((prev) => ({ ...prev, description: e.target.value }))
              }
              placeholder="What happened and why it matters..."
              className="mt-1.5 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 py-2.5 text-sm text-white placeholder:text-gray-400 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
            />
          </label>

          <div className="mt-1 flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 sm:col-span-2">
            <p className="text-sm text-slate-200">Visibility</p>
            <label className="inline-flex items-center gap-2 text-sm text-gray-100">
              <input
                type="checkbox"
                checked={form.is_public}
                onChange={(e) =>
                  setForm((prev) => ({ ...prev, is_public: e.target.checked }))
                }
                className="h-4 w-4 rounded border-white/20 bg-[#0b1220] accent-blue-500"
              />
              Public
            </label>
          </div>
        </div>
    </ScrollableModalShell>
      <ImageCropModal
        open={cropModalOpen}
        file={imageCrop.cropSourceFile}
        preset={CONTENT_IMAGE_CROP_PRESET}
        onCancel={imageCrop.handleCropCancel}
        onSave={imageCrop.handleCropSave}
      />
      <FeedbackModal {...feedbackModalProps} />
      <CreateAccountModal
        open={showCreateAccountModal}
        onClose={() => {
          if (!creatingAccount) setShowCreateAccountModal(false)
        }}
        onSave={handleCreateAccountSave}
      />
      <Modal
        open={payoutConfirmOpen}
        onClose={() => {
          if (!recordingPayout) {
            setPayoutConfirmOpen(false)
            pendingAchievementSaveRef.current = false
          }
        }}
        title="Record Payout"
        size="sm"
        footer={
          <div className="flex justify-end gap-3">
            <button
              type="button"
              onClick={() => {
                setPayoutConfirmOpen(false)
                pendingAchievementSaveRef.current = false
              }}
              className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={() => {
                setPayoutConfirmOpen(false)
                setPayoutSetupKey((key) => key + 1)
                setPayoutSetupOpen(true)
              }}
              className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-500"
            >
              Continue
            </button>
          </div>
        }
      >
        <p className="text-sm leading-relaxed text-gray-300">
          Recording a payout will begin a new payout cycle. Historical trades and
          lifetime statistics will remain unchanged. Current payout cycle progress
          will reset.
        </p>
      </Modal>
      {payoutSetupContext ? (
        <PayoutSetupModal
          key={payoutSetupKey}
          open={payoutSetupOpen}
          onClose={() => {
            if (!recordingPayout) {
              setPayoutSetupOpen(false)
              pendingAchievementSaveRef.current = false
            }
          }}
          onSubmit={handlePayoutSetupSubmit}
          busy={recordingPayout}
          accountBaseBalance={payoutSetupContext.startingBalance}
          balanceBeforePayout={payoutSetupContext.balanceBeforePayout}
          defaultDrawdownBehavior={payoutSetupContext.defaultDrawdownBehavior}
          defaultRememberDrawdownBehavior={
            payoutSetupContext.defaultRememberDrawdownBehavior
          }
          initialPayoutAmount={
            Number(String(form.payout_amount).replace(/,/g, "")) || undefined
          }
        />
      ) : null}
      {evalContinuanceModals}
    </>
  )
}
