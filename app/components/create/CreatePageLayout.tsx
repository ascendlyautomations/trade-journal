"use client"

import type { ReactNode } from "react"
import { useRouter } from "next/navigation"
import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import Button from "@/app/components/ui/Button"
import { ChevronLeft } from "lucide-react"

export type CreatePageLayoutProps = {
  title: string
  subtitle?: string
  backHref?: string
  onBack?: () => void
  primaryLabel: string
  onPrimary: () => void
  primaryDisabled?: boolean
  primaryBusy?: boolean
  secondaryLabel?: string
  onSecondary?: () => void
  preview?: ReactNode
  children: ReactNode
}

export default function CreatePageLayout({
  title,
  subtitle,
  backHref,
  onBack,
  primaryLabel,
  onPrimary,
  primaryDisabled = false,
  primaryBusy = false,
  secondaryLabel = "Cancel",
  onSecondary,
  preview,
  children,
}: CreatePageLayoutProps) {
  const router = useRouter()

  function handleBack() {
    if (onBack) {
      onBack()
      return
    }
    if (backHref) {
      router.push(backHref)
      return
    }
    router.back()
  }

  function handleSecondary() {
    if (onSecondary) {
      onSecondary()
      return
    }
    handleBack()
  }

  return (
    <div
      data-tt-create-page
      className="tt-add-trade tt-phase4-dark min-h-[calc(100dvh-var(--app-header-offset))] bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100"
    >
      <div className="mx-auto flex w-full max-w-6xl flex-col px-4 pb-[max(1.5rem,var(--safe-area-bottom))] pt-4 sm:px-6 sm:pt-6">
        <header className="flex shrink-0 flex-col gap-4 border-b border-white/10 pb-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex min-w-0 items-start gap-2">
            <button
              type="button"
              onClick={handleBack}
              className="mt-0.5 inline-flex shrink-0 items-center gap-1 rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 text-sm text-gray-200 transition hover:bg-white/10"
              aria-label="Go back"
            >
              <ChevronLeft className="h-4 w-4" aria-hidden />
              <span className="hidden sm:inline">Back</span>
            </button>
            <div className="min-w-0">
              <h1 className="text-xl font-semibold tracking-tight text-white sm:text-2xl">
                {title}
              </h1>
              {subtitle ? (
                <p className="mt-1 text-sm text-gray-300">{subtitle}</p>
              ) : null}
            </div>
          </div>

          <div className="flex shrink-0 flex-col-reverse gap-2 sm:flex-row sm:items-center">
            <Button
              type="button"
              variant="secondary"
              size="md"
              onClick={handleSecondary}
              disabled={primaryBusy}
              className="h-10"
            >
              {secondaryLabel}
            </Button>
            <Button
              type="button"
              variant="primary"
              size="md"
              onClick={onPrimary}
              disabled={primaryDisabled || primaryBusy}
              className="h-10 min-w-[7rem]"
            >
              {primaryBusy ? "Working…" : primaryLabel}
            </Button>
          </div>
        </header>

        <div
          className={
            preview
              ? "mt-6 grid flex-1 gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(280px,360px)] lg:items-start"
              : "mt-6 flex-1"
          }
        >
          <div className="min-w-0 rounded-xl border border-white/10 bg-white/5 p-4 shadow-lg shadow-black/20 sm:p-6">
            {children}
          </div>
          {preview ? (
            <aside className="lg:sticky lg:top-[calc(var(--app-header-offset)+1rem)]">
              <div className="rounded-xl border border-white/10 bg-white/5 p-4 sm:p-5">
                <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Preview
                </p>
                {preview}
              </div>
            </aside>
          ) : null}
        </div>

        <p className="mt-6 text-center text-xs text-gray-500">
          Need full trade journaling?{" "}
          <IntentPrefetchLink
            href="/app"
            className="text-blue-300 underline-offset-2 hover:underline"
          >
            Add Trade
          </IntentPrefetchLink>
        </p>
      </div>
    </div>
  )
}
