"use client"

import { useEffect, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { cn } from "./cn"

export type ModalProps = {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
  footer?: ReactNode
  /** Panel width cap */
  size?: "sm" | "md" | "lg"
  className?: string
  panelClassName?: string
  backdropClassName?: string
}

const sizeClasses = {
  sm: "max-w-sm",
  md: "max-w-lg",
  lg: "max-w-2xl",
}

export default function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  size = "md",
  className,
  panelClassName,
  backdropClassName,
}: ModalProps) {
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [open, onClose])

  useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = "hidden"
    return () => {
      document.body.style.overflow = prev
    }
  }, [open])

  if (!open || !mounted) return null

  return createPortal(
    <div
      className={cn(
        "fixed inset-0 z-[10050] flex items-center justify-center p-4",
        className
      )}
      role="presentation"
      onClick={onClose}
    >
      <div
        className={cn(
          "absolute inset-0 bg-black/50 backdrop-blur-sm",
          backdropClassName
        )}
        aria-hidden
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cn(
          "relative w-full rounded-xl border border-white/10 bg-[#0f172a] p-6 text-gray-100 shadow-xl",
          sizeClasses[size],
          panelClassName
        )}
        onClick={(e) => e.stopPropagation()}
      >
        {title ? (
          <h2 className="mb-4 text-lg font-semibold text-white">{title}</h2>
        ) : null}
        <div>{children}</div>
        {footer ? <div className="mt-4">{footer}</div> : null}
      </div>
    </div>,
    document.body
  )
}
