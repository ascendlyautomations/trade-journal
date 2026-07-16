"use client"

import { useEffect, useRef, useState } from "react"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"
import Modal from "@/app/components/ui/Modal"
import {
  mapInAppPasswordUpdateError,
  PASSWORD_MIN_LENGTH,
  validatePasswordPair,
} from "@/lib/passwordResetRecovery"
import { markProfileHasEmailPassword } from "@/lib/emailPasswordProfile"
import { supabase } from "@/lib/supabaseClient"

type Props = {
  open: boolean
  userId: string | undefined
  onClose: () => void
  onSuccess: () => void
}

const inputClassName =
  "w-full rounded-xl border border-white/10 bg-black/30 p-3 placeholder:text-gray-400"

export default function CreatePasswordModal({
  open,
  userId,
  onClose,
  onSuccess,
}: Props) {
  const [password, setPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [fieldErrors, setFieldErrors] = useState<{
    password?: string
    confirmPassword?: string
  }>({})
  const [submitError, setSubmitError] = useState("")
  const [saving, setSaving] = useState(false)
  const savingRef = useRef(false)

  useEffect(() => {
    if (!open) return
    setPassword("")
    setConfirmPassword("")
    setFieldErrors({})
    setSubmitError("")
    setSaving(false)
    savingRef.current = false
  }, [open])

  function handlePasswordChange(value: string) {
    setPassword(value)
    setSubmitError("")
    setFieldErrors(validatePasswordPair(value, confirmPassword))
  }

  function handleConfirmPasswordChange(value: string) {
    setConfirmPassword(value)
    setSubmitError("")
    setFieldErrors(validatePasswordPair(password, value))
  }

  async function handleSave() {
    const trimmedPassword = password.trim()
    const trimmedConfirm = confirmPassword.trim()

    const validation = validatePasswordPair(trimmedPassword, trimmedConfirm)
    const passwordError =
      trimmedPassword.length < PASSWORD_MIN_LENGTH
        ? `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
        : validation.password
    const confirmError =
      trimmedPassword !== trimmedConfirm
        ? "Passwords do not match."
        : validation.confirmPassword

    if (passwordError || confirmError) {
      setFieldErrors({
        password: passwordError,
        confirmPassword: confirmError,
      })
      return
    }

    if (savingRef.current || saving) return

    savingRef.current = true
    setSaving(true)
    setSubmitError("")

    try {
      const { error } = await supabase.auth.updateUser({
        password: trimmedPassword,
      })

      if (error) {
        setSubmitError(mapInAppPasswordUpdateError(error))
        return
      }

      if (!userId?.trim()) {
        setSubmitError("Could not save password status. Please try again.")
        return
      }

      const marked = await markProfileHasEmailPassword(supabase, userId)
      if (!marked.ok) {
        setSubmitError(marked.message)
        return
      }

      onSuccess()
      onClose()
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Create password"
      size="md"
      footer={
        <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            className="rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-white/10 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => void handleSave()}
            disabled={saving}
            className="rounded-xl bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
          >
            {saving ? "Saving…" : "Save"}
          </button>
        </div>
      }
    >
      <p className="mb-4 text-sm text-gray-400">
        Create a password so you can also sign in using your email and password,
        in addition to Google.
      </p>

      <div className="space-y-4">
        <div>
          <label
            htmlFor="create-password-new"
            className="mb-1 block text-sm text-gray-400"
          >
            New password
          </label>
          <AuthPasswordInput
            id="create-password-new"
            autoComplete="new-password"
            value={password}
            onChange={(e) => handlePasswordChange(e.target.value)}
            placeholder="Enter new password"
            className={inputClassName}
          />
          {fieldErrors.password ? (
            <p className="mt-1 text-sm text-red-300">{fieldErrors.password}</p>
          ) : null}
        </div>

        <div>
          <label
            htmlFor="create-password-confirm"
            className="mb-1 block text-sm text-gray-400"
          >
            Confirm password
          </label>
          <AuthPasswordInput
            id="create-password-confirm"
            autoComplete="new-password"
            value={confirmPassword}
            onChange={(e) => handleConfirmPasswordChange(e.target.value)}
            placeholder="Confirm new password"
            className={inputClassName}
          />
          {fieldErrors.confirmPassword ? (
            <p className="mt-1 text-sm text-red-300">
              {fieldErrors.confirmPassword}
            </p>
          ) : null}
        </div>

        {submitError ? (
          <p className="text-sm text-red-300">{submitError}</p>
        ) : null}
      </div>
    </Modal>
  )
}
