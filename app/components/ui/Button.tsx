"use client"

import type { ButtonHTMLAttributes } from "react"
import {
  UI_BUTTON_GHOST,
  UI_BUTTON_PRIMARY,
  UI_BUTTON_SECONDARY,
} from "@/lib/uiPrimitiveStyles"
import { cn } from "./cn"

export type ButtonVariant = "primary" | "secondary" | "accent" | "ghost"

export type ButtonSize = "sm" | "md" | "lg"

/** Solid primary fill/hover — compose with padding/radius at call sites. */
export const SOLID_PRIMARY_BUTTON_CORE = UI_BUTTON_PRIMARY

const variantClasses: Record<ButtonVariant, string> = {
  primary: UI_BUTTON_PRIMARY,
  secondary: UI_BUTTON_SECONDARY,
  accent: UI_BUTTON_PRIMARY,
  ghost: UI_BUTTON_GHOST,
}

const sizeClasses: Record<ButtonSize, string> = {
  sm: "px-3 py-1.5 text-xs font-medium rounded-lg",
  md: "px-4 py-2 text-sm font-semibold rounded-lg",
  lg: "px-4 py-3 text-base font-semibold rounded-xl",
}

export type ButtonVariantProps = {
  variant?: ButtonVariant
  size?: ButtonSize
  fullWidth?: boolean
}

export function buttonVariants({
  variant = "primary",
  size = "md",
  fullWidth = false,
  className,
}: ButtonVariantProps & { className?: string } = {}) {
  return cn(
    "inline-flex items-center justify-center transition disabled:cursor-not-allowed disabled:opacity-60",
    variantClasses[variant],
    sizeClasses[size],
    fullWidth && "w-full",
    className
  )
}

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> &
  ButtonVariantProps

export default function Button({
  variant = "primary",
  size = "md",
  fullWidth = false,
  className,
  type = "button",
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      className={buttonVariants({ variant, size, fullWidth, className })}
      {...props}
    />
  )
}
