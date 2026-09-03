"use client"

import type { ButtonHTMLAttributes } from "react"
import AppleIcon from "@/app/components/ui/AppleIcon"
import { cn } from "@/app/components/ui/cn"

export type AppleSignInButtonLabel = "sign-in" | "sign-up" | "continue"

const LABEL_TEXT: Record<AppleSignInButtonLabel, string> = {
  "sign-in": "Sign in with Apple",
  "sign-up": "Sign up with Apple",
  continue: "Continue with Apple",
}

/**
 * Dark-theme Sign in with Apple button — white label on black per Apple HIG.
 * @see https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
 */
export const APPLE_SIGN_IN_BUTTON_CLASS =
  "inline-flex min-h-10 w-full items-center justify-center gap-3 rounded bg-black px-3 py-2.5 text-sm font-medium leading-5 text-white shadow-none transition hover:bg-[#1a1a1a] active:bg-[#2a2a2a] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-black"

export type AppleSignInButtonProps = Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "children"
> & {
  label?: AppleSignInButtonLabel
  loading?: boolean
  loadingText?: string
}

export default function AppleSignInButton({
  label = "continue",
  loading = false,
  loadingText = "Redirecting…",
  className,
  disabled,
  type = "button",
  ...props
}: AppleSignInButtonProps) {
  const labelText = LABEL_TEXT[label]
  const isDisabled = disabled || loading

  return (
    <button
      type={type}
      disabled={isDisabled}
      aria-busy={loading || undefined}
      aria-label={loading ? `${labelText}. ${loadingText}` : labelText}
      className={cn(APPLE_SIGN_IN_BUTTON_CLASS, className)}
      {...props}
    >
      <span
        className="flex h-5 w-5 shrink-0 items-center justify-center"
        aria-hidden
      >
        <AppleIcon className="h-[18px] w-[18px]" />
      </span>
      <span className="truncate">{loading ? loadingText : labelText}</span>
    </button>
  )
}
