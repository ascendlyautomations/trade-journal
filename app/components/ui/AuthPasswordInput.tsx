"use client"

import { useState } from "react"
import { cn } from "./cn"

type AuthPasswordInputProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "type"
>

const MARGIN_CLASS_PREFIXES = [
  "m-",
  "mx-",
  "my-",
  "mt-",
  "mr-",
  "mb-",
  "ml-",
  "ms-",
  "me-",
] as const

function splitMarginClasses(className?: string): {
  inputClassName: string
  outerClassName: string
} {
  if (!className) return { inputClassName: "", outerClassName: "" }

  const inputClasses: string[] = []
  const outerClasses: string[] = []

  for (const token of className.split(/\s+/).filter(Boolean)) {
    if (MARGIN_CLASS_PREFIXES.some((prefix) => token.startsWith(prefix))) {
      outerClasses.push(token)
    } else {
      inputClasses.push(token)
    }
  }

  return {
    inputClassName: inputClasses.join(" "),
    outerClassName: outerClasses.join(" "),
  }
}

function EyeIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn("block h-5 w-5 shrink-0", className)}
      aria-hidden
    >
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  )
}

function EyeOffIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn("block h-5 w-5 shrink-0", className)}
      aria-hidden
    >
      <path d="M9.88 9.88a3 3 0 1 0 4.24 4.24" />
      <path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68" />
      <path d="M6.61 6.61A13.52 13.52 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61" />
      <line x1="2" x2="22" y1="2" y2="22" />
    </svg>
  )
}

/** Auth password field with styled show/hide toggle (replaces browser-native reveal). */
export default function AuthPasswordInput({
  className,
  ...props
}: AuthPasswordInputProps) {
  const [visible, setVisible] = useState(false)
  const { inputClassName, outerClassName } = splitMarginClasses(className)

  return (
    <div className={cn("w-full", outerClassName)}>
      <div className="relative">
        <input
          {...props}
          type={visible ? "text" : "password"}
          className={cn("tt-auth-password w-full pr-11", inputClassName)}
        />
        <button
          type="button"
          tabIndex={-1}
          aria-label={visible ? "Hide password" : "Show password"}
          aria-pressed={visible}
          onClick={() => setVisible((prev) => !prev)}
          className="absolute inset-y-0 right-3 flex items-center justify-center p-0 leading-none text-gray-400 transition hover:text-gray-200"
        >
          {visible ? <EyeOffIcon /> : <EyeIcon />}
        </button>
      </div>
    </div>
  )
}
