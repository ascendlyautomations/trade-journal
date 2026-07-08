"use client"

import type { ButtonHTMLAttributes } from "react"
import GoogleGIcon from "@/app/components/ui/GoogleGIcon"
import { cn } from "@/app/components/ui/cn"

/** Google-recommended CTA text variants. */
export type GoogleSignInButtonLabel = "sign-in" | "sign-up" | "continue"

const LABEL_TEXT: Record<GoogleSignInButtonLabel, string> = {
  "sign-in": "Sign in with Google",
  "sign-up": "Sign up with Google",
  continue: "Continue with Google",
}

/**
 * Light-theme Sign in with Google button per Google Identity branding guidelines.
 * @see https://developers.google.com/identity/branding-guidelines
 */
export const GOOGLE_SIGN_IN_BUTTON_CLASS =
  "inline-flex min-h-10 w-full items-center justify-center gap-3 rounded border border-[#747775] bg-white px-3 py-2.5 text-sm font-medium leading-5 text-[#1F1F1F] shadow-none transition hover:bg-[#f8f9fa] active:bg-[#f1f3f4] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#1F1F1F] disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-white"

export type GoogleSignInButtonProps = Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "children"
> & {
  label?: GoogleSignInButtonLabel
  loading?: boolean
  loadingText?: string
}

export default function GoogleSignInButton({
  label = "continue",
  loading = false,
  loadingText = "Redirecting…",
  className,
  disabled,
  type = "button",
  ...props
}: GoogleSignInButtonProps) {
  const labelText = LABEL_TEXT[label]
  const isDisabled = disabled || loading

  return (
    <button
      type={type}
      disabled={isDisabled}
      aria-busy={loading || undefined}
      aria-label={loading ? `${labelText}. ${loadingText}` : labelText}
      className={cn(GOOGLE_SIGN_IN_BUTTON_CLASS, className)}
      style={{ fontFamily: '"Google Sans", Roboto, Arial, sans-serif' }}
      {...props}
    >
      <span
        className="flex h-5 w-5 shrink-0 items-center justify-center bg-white"
        aria-hidden
      >
        <GoogleGIcon className="h-5 w-5" />
      </span>
      <span className="truncate">{loading ? loadingText : labelText}</span>
    </button>
  )
}
