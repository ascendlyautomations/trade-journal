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
import { uploadToSupabaseStorageWithProgress } from "@/lib/supabaseStorageUploadWithProgress"
import {
  createMonotonicReporter,
  mapUploadBytesToPercent,
} from "@/lib/uploadProgress/reportProgress"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import ImageCropModal from "@/app/components/ImageCropModal"
import { useImageCropUpload } from "@/lib/useImageCropUpload"

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
    onValidationError: setError,
  })
  const fileInputRef = imageCrop.fileInputRef
  const uploadingRef = useRef(false)
  const { runUpload } = useUploadProgress()

  const resetForm = useCallback(() => {
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
        metadata: editingAchievement.metadata ?? null,
      })
    } else {
      const defaultDate = resolveNewAchievementDateInputValue(initialValues)
      setForm(
        mergeInitialForm({
          ...initialValues,
          achieved_at: defaultDate,
        })
      )
    }
    setFile(null)
    setPreviewUrl(null)
    setRemoveImage(false)
    setError(null)
  }, [editingAchievement, initialValues])

  useLayoutEffect(() => {
    if (!open) return
    resetForm()
  }, [open, resetForm])

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
    if (busy || uploadingRef.current || imageCrop.cropSourceFile) return
    onClose()
  }

  const cropModalOpen = imageCrop.cropSourceFile != null

  async function saveAchievement() {
    if (isDemoModeActive()) {
      requestDemoSignup("upload")
      return
    }
    if (!userId || !form.title.trim() || !form.achievement_type.trim()) return
    if (uploadingRef.current) return

    const achievementType = canonicalAchievementType(form.achievement_type)
    const payoutAmount = isPayoutAchievementType(achievementType)
      ? Number(form.payout_amount)
      : null
    if (
      isPayoutAchievementType(achievementType) &&
      (!Number.isFinite(payoutAmount) || (payoutAmount as number) <= 0)
    ) {
      setError("Please enter a valid payout amount.")
      return
    }

    setError(null)
    uploadingRef.current = true

    const snapshotForm = { ...form }
    const snapshotFile = file
    const snapshotRemoveImage = removeImage
    const snapshotEditingId = editingId

    try {
      await runUpload({
        title: snapshotFile
          ? editingId
            ? "Updating Achievement"
            : "Uploading Achievement"
          : editingId
            ? "Updating Achievement"
            : "Saving Achievement",
        onDismissCompose: onClose,
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

            report({ percent: 10, stage: "Processing image…" })

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

            report({ percent: 18, stage: "Uploading media…" })
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
                    stage: "Uploading media…",
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
            report({ percent: 40, stage: "Saving achievement…" })
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
            account_type: null,
            account_name: snapshotForm.account_name?.trim() || null,
            account_size: snapshotForm.account_size?.trim() || null,
            mode: null,
            firm: snapshotForm.firm?.trim() || null,
            achieved_at: snapshotForm.achieved_at || null,
            image_url: imageUrl,
            is_public: snapshotForm.is_public,
            is_featured: snapshotForm.is_featured,
            metadata: normalizeAchievementMetadata(snapshotForm.metadata),
          }

          report({ percent: 82, stage: "Creating record…" })

          const query = snapshotEditingId
            ? supabase
                .from("achievements")
                .update(payload)
                .eq("id", snapshotEditingId)
                .eq("user_id", userId)
            : supabase.from("achievements").insert(payload)

          const { error: saveErr } = await query
          if (saveErr) {
            console.error("[achievements] save failed", saveErr)
            throw new Error(saveErr.message || "Could not save achievement.")
          }

          report({ percent: 95, stage: "Finishing…" })
          await onSaved?.()
        },
      })
    } catch {
      // Overlay handles retry/cancel.
    } finally {
      uploadingRef.current = false
    }
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
            <select
              value={form.achievement_type}
              disabled={lockAchievementType}
              onChange={(e) =>
                setForm((prev) => ({ ...prev, achievement_type: e.target.value }))
              }
              className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20 disabled:cursor-not-allowed disabled:opacity-70"
            >
              {ACHIEVEMENT_TYPE_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          <label className="text-xs text-gray-300">
            Title
            <input
              type="text"
              value={form.title}
              onChange={(e) => setForm((prev) => ({ ...prev, title: e.target.value }))}
              placeholder="e.g. First payout from Apex"
              className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
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
                className="mt-1.5 h-11 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
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
                    Remove image
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
              className="mt-1.5 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 py-2.5 text-sm text-white placeholder:text-slate-500 outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20"
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
    </>
  )
}
