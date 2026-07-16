"use client"

import { useEffect, useRef, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"
import {
  establishPasswordResetRecovery,
  isPasswordPairValid,
  mapPasswordUpdateError,
  PASSWORD_MIN_LENGTH,
  validatePasswordPair,
  type PasswordResetRecoveryStatus,
} from "@/lib/passwordResetRecovery"
import { supabase } from "@/lib/supabaseClient"

type PagePhase = "loading" | "ready" | "invalid" | "success"

const inputClassName =
  "w-full px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"

export default function ResetPasswordPage() {
  const router = useRouter()
  const [phase, setPhase] = useState<PagePhase>("loading")
  const recoveryReadyRef = useRef(false)

  const [password, setPassword] = useState("")
  const [confirmPassword, setConfirmPassword] = useState("")
  const [fieldErrors, setFieldErrors] = useState<{
    password?: string
    confirmPassword?: string
  }>({})
  const [submitError, setSubmitError] = useState("")
  const [isSubmitting, setIsSubmitting] = useState(false)
  const submittingRef = useRef(false)

  useEffect(() => {
    let cancelled = false

    void establishPasswordResetRecovery(supabase).then((status: PasswordResetRecoveryStatus) => {
      if (cancelled) return
      recoveryReadyRef.current = status === "ready"
      setPhase(status === "ready" ? "ready" : "invalid")
    })

    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (phase !== "success") return

    const timeoutId = window.setTimeout(() => {
      void goToLogin()
    }, 4000)

    return () => window.clearTimeout(timeoutId)
  }, [phase])

  async function goToLogin() {
    await supabase.auth.signOut()
    router.push("/login?reset=success")
  }

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

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()

    const validation = validatePasswordPair(password, confirmPassword)
    const passwordError =
      password.length < PASSWORD_MIN_LENGTH
        ? `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`
        : validation.password
    const confirmError =
      password !== confirmPassword ? "Passwords do not match." : validation.confirmPassword

    if (passwordError || confirmError) {
      setFieldErrors({
        password: passwordError,
        confirmPassword: confirmError,
      })
      return
    }

    if (!recoveryReadyRef.current || phase !== "ready") return
    if (submittingRef.current || isSubmitting) return

    submittingRef.current = true
    setIsSubmitting(true)
    setSubmitError("")

    try {
      const {
        data: { session },
      } = await supabase.auth.getSession()

      if (!session) {
        setPhase("invalid")
        recoveryReadyRef.current = false
        return
      }

      const { error } = await supabase.auth.updateUser({ password })

      if (error) {
        setSubmitError(mapPasswordUpdateError(error))
        if (
          mapPasswordUpdateError(error).includes("expired") ||
          mapPasswordUpdateError(error).includes("reset link")
        ) {
          recoveryReadyRef.current = false
        }
        return
      }

      recoveryReadyRef.current = false
      setPhase("success")
    } catch {
      setSubmitError("Network error. Check your connection and try again.")
    } finally {
      submittingRef.current = false
      setIsSubmitting(false)
    }
  }

  const canSubmit =
    phase === "ready" &&
    recoveryReadyRef.current &&
    isPasswordPairValid(password, confirmPassword) &&
    !isSubmitting

  return (
    <div className="relative flex min-h-screen items-center justify-center text-white">
      <img
        src="/tradetrax-bg.webp"
        alt=""
        className="absolute inset-0 h-full w-full object-cover"
      />
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" />

      <Link
        href="/login"
        className="absolute left-3 top-3 z-20 inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/10 text-base leading-none text-gray-200 backdrop-blur-md transition hover:bg-white/15 hover:text-white md:left-6 md:top-6 md:h-auto md:min-h-[44px] md:w-auto md:gap-2 md:px-4 md:py-2 md:text-sm md:font-medium"
        aria-label="Return to login"
      >
        <span aria-hidden="true">←</span>
        <span className="hidden md:inline">Back</span>
      </Link>

      <div className="relative z-10 flex w-full max-w-6xl flex-col items-center justify-between px-6 md:flex-row">
        <div className="mb-10 max-w-lg text-center md:mb-0 md:text-left">
          <p className="mb-4 text-sm tracking-widest text-blue-300">WELCOME TO</p>
          <h1 className="mb-4 text-5xl font-bold text-blue-300">
            TradeTraxs
          </h1>
          <p className="text-lg text-gray-300">Track. Analyze. Socialize. Dominate your trading.</p>
        </div>

        <div className="w-full max-w-md rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl">
          {phase === "loading" ? (
            <div className="py-6 text-center">
              <p className="text-lg font-semibold">Loading...</p>
              <p className="mt-2 text-sm text-gray-400">Verifying password reset link...</p>
            </div>
          ) : null}

          {phase === "invalid" ? (
            <div className="text-center">
              <h2 className="text-xl font-semibold">Reset Link Invalid</h2>
              <p className="mt-3 text-sm text-gray-300">
                This password reset link is invalid or has expired.
              </p>
              <Link
                href="/login"
                className="mt-6 block w-full rounded-xl bg-blue-500 py-3 text-center font-semibold text-white transition hover:bg-blue-600 hover:scale-105"
              >
                Request New Reset Link
              </Link>
              <Link
                href="/login"
                className="mt-3 block w-full rounded-xl border border-white/10 bg-white/5 py-3 text-center font-semibold text-gray-200 transition hover:bg-white/10"
              >
                Return to Login
              </Link>
            </div>
          ) : null}

          {phase === "success" ? (
            <div className="text-center">
              <p className="text-2xl font-semibold text-green-400">✓ Password Updated</p>
              <p className="mt-3 text-sm text-gray-300">
                Your password has been successfully updated.
              </p>
              <button
                type="button"
                onClick={() => void goToLogin()}
                className="mt-6 w-full rounded-xl bg-blue-500 py-3 font-semibold text-white transition hover:bg-blue-600 hover:scale-105"
              >
                Return to Login
              </button>
              <p className="mt-3 text-xs text-gray-400">Redirecting to login shortly…</p>
            </div>
          ) : null}

          {phase === "ready" ? (
            <>
              <h2 className="mb-2 text-center text-xl font-semibold">Reset your password</h2>
              <p className="mb-6 text-center text-sm text-gray-400">
                Choose a strong password you have not used elsewhere.
              </p>

              <form onSubmit={(e) => void handleSubmit(e)} className="space-y-4">
                <div>
                  <label htmlFor="reset-new-password" className="mb-1 block text-sm text-gray-400">
                    New Password
                  </label>
                  <AuthPasswordInput
                    id="reset-new-password"
                    autoComplete="new-password"
                    placeholder="New password"
                    value={password}
                    onChange={(e) => handlePasswordChange(e.target.value)}
                    className={inputClassName}
                  />
                  {fieldErrors.password ? (
                    <p className="mt-1 text-xs text-red-400">{fieldErrors.password}</p>
                  ) : (
                    <p className="mt-1 text-xs text-gray-400">
                      Must be at least {PASSWORD_MIN_LENGTH} characters.
                    </p>
                  )}
                </div>

                <div>
                  <label
                    htmlFor="reset-confirm-password"
                    className="mb-1 block text-sm text-gray-400"
                  >
                    Confirm Password
                  </label>
                  <AuthPasswordInput
                    id="reset-confirm-password"
                    autoComplete="new-password"
                    placeholder="Confirm password"
                    value={confirmPassword}
                    onChange={(e) => handleConfirmPasswordChange(e.target.value)}
                    className={inputClassName}
                  />
                  {fieldErrors.confirmPassword ? (
                    <p className="mt-1 text-xs text-red-400">{fieldErrors.confirmPassword}</p>
                  ) : null}
                </div>

                {submitError ? (
                  <p className="text-sm text-red-400" role="alert">
                    {submitError}
                  </p>
                ) : null}

                <button
                  type="submit"
                  disabled={!canSubmit}
                  className="w-full rounded-xl bg-blue-500 py-3 font-semibold text-white transition hover:bg-blue-600 hover:scale-105 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 disabled:hover:scale-100"
                >
                  {isSubmitting ? "Updating…" : "Update Password"}
                </button>
              </form>
            </>
          ) : null}
        </div>
      </div>
    </div>
  )
}
