"use client"

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  normalizeAchievementDateInputValue,
  resolveNewAchievementDateInputValue,
} from "@/lib/achievementDate"
import {
  type Achievement,
  badgeKeyFromType,
  categoryFromType,
  normalizeAchievementType,
} from "@/lib/achievements"

export type AchievementFormState = {
  achievement_type: string
  title: string
  description: string
  payout_amount: string
  achieved_at: string
  image_url: string | null
  is_public: boolean
  is_featured: boolean
}

export const EMPTY_ACHIEVEMENT_FORM: AchievementFormState = {
  achievement_type: "payout",
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
  const fileInputRef = useRef<HTMLInputElement | null>(null)

  const resetForm = useCallback(() => {
    if (editingAchievement) {
      const savedDate = normalizeAchievementDateInputValue(
        editingAchievement.achieved_at
      )
      setForm({
        achievement_type: normalizeAchievementType(editingAchievement.achievement_type),
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

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  function handleClose() {
    if (busy) return
    onClose()
  }

  async function saveAchievement() {
    if (!userId || !form.title.trim() || !form.achievement_type.trim()) return
    const normalizedType = normalizeAchievementType(form.achievement_type)
    const payoutAmount =
      normalizedType === "payout" ? Number(form.payout_amount) : null
    if (
      normalizedType === "payout" &&
      (!Number.isFinite(payoutAmount) || (payoutAmount as number) <= 0)
    ) {
      setError("Please enter a valid payout amount.")
      return
    }
    setBusy(true)
    setError(null)

    let imageUrl = form.image_url
    if (removeImage) {
      imageUrl = null
    }

    if (file) {
      const ext = file.name.includes(".")
        ? file.name.split(".").pop()?.toLowerCase() || "jpg"
        : "bin"
      const safeBase = file.name
        .replace(/\.[^/.]+$/, "")
        .toLowerCase()
        .replace(/[^a-z0-9-_]+/g, "-")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "")
      let uploadFile: File = file
      if (file.type?.startsWith("image/")) {
        uploadFile = await compressImage(file)
      }
      const uploadName = uploadFile.type?.startsWith("image/")
        ? uploadFile.name
        : `${safeBase || "image"}.${ext}`
      const filePath = `achievements/${userId}/${Date.now()}-${uploadName}`

      const { error: uploadErr } = await supabase.storage
        .from("screenshots")
        .upload(filePath, uploadFile, { upsert: true })
      if (uploadErr) {
        setBusy(false)
        setError(uploadErr.message || "Could not upload image.")
        return
      }

      const { data: publicData } = supabase.storage
        .from("screenshots")
        .getPublicUrl(filePath)
      imageUrl = publicData.publicUrl
    }

    const payload = {
      user_id: userId,
      achievement_type: normalizedType,
      title: form.title.trim(),
      description: form.description.trim() || null,
      badge_key: badgeKeyFromType(form.achievement_type),
      category: categoryFromType(form.achievement_type),
      tier: null,
      value_numeric: normalizedType === "payout" ? payoutAmount : null,
      value_text:
        normalizedType === "payout" && payoutAmount != null
          ? `+$${Math.abs(payoutAmount).toLocaleString(undefined, {
              minimumFractionDigits: 0,
              maximumFractionDigits: 2,
            })}`
          : null,
      currency: normalizedType === "payout" ? "USD" : null,
      account_type: null,
      account_name: null,
      account_size: null,
      mode: null,
      firm: null,
      achieved_at: form.achieved_at || null,
      image_url: imageUrl,
      is_public: form.is_public,
      is_featured: form.is_featured,
    }

    const query = editingId
      ? supabase
          .from("achievements")
          .update(payload)
          .eq("id", editingId)
          .eq("user_id", userId)
      : supabase.from("achievements").insert(payload)

    const { error: saveErr } = await query
    setBusy(false)
    if (saveErr) {
      console.error("[achievements] save failed", saveErr)
      setError(saveErr.message || "Could not save achievement.")
      return
    }

    await onSaved?.()
    onClose()
  }

  if (!open) return null

  const heading = dialogTitle ?? (editingId ? "Edit Achievement" : "Add Achievement")
  const subheading =
    dialogSubtitle ??
    "Capture your achievements with a quick summary and image."
  const submitLabel =
    saveLabel ?? (busy ? "Saving..." : editingId ? "Update Achievement" : "Save Achievement")

  return (
    <div
      className="fixed inset-0 z-[150] flex items-end justify-center bg-black/75 p-2 backdrop-blur-md sm:items-center sm:p-4"
      onClick={handleClose}
    >
      <div
        className="max-h-[92vh] w-full max-w-3xl overflow-y-auto rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] p-4 shadow-2xl shadow-blue-900/20 sm:p-6"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={heading}
      >
        <div className="mb-3 border-b border-white/10 pb-3">
          <h2 className="text-xl font-semibold tracking-tight text-white">{heading}</h2>
          <p className="mt-0.5 text-sm text-slate-300">{subheading}</p>
        </div>

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
              <option value="payout">Payout</option>
              <option value="passed_eval">Passed Eval</option>
              <option value="milestone">Milestone</option>
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
          {normalizeAchievementType(form.achievement_type) === "payout" ? (
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
                  setFile(selected)
                  if (selected) setRemoveImage(false)
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
                <img
                  src={previewUrl}
                  alt="Selected preview"
                  className="mt-2 max-h-40 w-full rounded-md border border-white/10 object-cover"
                />
              ) : form.image_url && !removeImage ? (
                <div className="mt-2 space-y-2">
                  <img
                    src={form.image_url}
                    alt="Current achievement image"
                    className="max-h-40 w-full rounded-md border border-white/10 object-cover"
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

        <div className="mt-5 flex flex-col-reverse gap-2 border-t border-white/10 pt-4 sm:flex-row sm:justify-end">
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
            className="h-10 rounded-lg bg-gradient-to-r from-blue-500 to-emerald-500 px-4 text-sm font-semibold text-white transition hover:from-blue-400 hover:to-emerald-400 disabled:opacity-60"
          >
            {submitLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
