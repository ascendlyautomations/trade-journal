"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { usePathname } from "next/navigation"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import {
  isTradovateLoginImportDismissedThisSession,
  isTradovateLoginImportPromptPath,
  isWithinTradovateLoginImportPromptCooldown,
  markTradovateLoginImportDismissedThisSession,
  markTradovateLoginImportPromptShown,
} from "@/lib/brokerImport/tradovateLoginImportSession"
import { queueBrokerEnrichment } from "@/lib/brokerEnrichment/queueBrokerEnrichment"
import { invalidateBrokerEnrichmentPendingCount } from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"
import { invalidateTradesCache } from "@/lib/appDataCache"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import ActionButton from "@/app/components/ui/ActionButton"

type LinkedAccount = {
  mappingId: string
  connectionId: string
  brokerAccountLabel: string | null
  tradetraxsAccountName: string | null
}

type FlowStep =
  | "closed"
  | "prompt"
  | "select_accounts"
  | "importing"
  | "caught_up"
  | "error"

function TradovateImportPromptAccountCard({
  accounts,
}: {
  accounts: LinkedAccount[]
}) {
  if (accounts.length > 1) {
    return (
      <div className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3">
        <p className="text-xs font-medium text-gray-400">Tradovate</p>
        <p className="mt-1 truncate text-sm font-medium text-white">
          {accounts.length} linked accounts
        </p>
      </div>
    )
  }

  const acc = accounts[0]
  if (!acc) return null

  const tradetraxsName = acc.tradetraxsAccountName?.trim() || null
  const brokerLabel = acc.brokerAccountLabel?.trim() || null
  const primaryLine = tradetraxsName || brokerLabel || "Linked account"
  const secondaryLine =
    tradetraxsName && brokerLabel && brokerLabel !== tradetraxsName ? brokerLabel : null

  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3">
      <p className="text-xs font-medium text-gray-400">Tradovate</p>
      <p className="mt-1 truncate text-sm font-medium text-white" title={primaryLine}>
        {primaryLine}
      </p>
      {secondaryLine ? (
        <p className="mt-0.5 truncate text-xs text-gray-500" title={secondaryLine}>
          {secondaryLine}
        </p>
      ) : null}
    </div>
  )
}

export default function BrokerTradovateLoginImportGate() {
  const pathname = usePathname()
  const { user, profile, loading: profileLoading } = useUserProfile()
  const evaluatedRef = useRef(false)
  const [step, setStep] = useState<FlowStep>("closed")
  const [linkedAccounts, setLinkedAccounts] = useState<LinkedAccount[]>([])
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [dontRemind, setDontRemind] = useState(false)
  const [importError, setImportError] = useState<string | null>(null)

  const closeAll = useCallback(() => {
    setStep("closed")
    setImportError(null)
  }, [])

  const saveDontRemindIfNeeded = useCallback(async () => {
    if (!dontRemind || !user?.id) return
    const headers = {
      ...(await supabaseBearerHeaders()),
      "Content-Type": "application/json",
    }
    await fetch("/api/integrations/tradovate/import/reminder", {
      method: "PATCH",
      headers,
      body: JSON.stringify({ optOut: true }),
    })
  }, [dontRemind, user?.id])

  const runImport = useCallback(
    async (mappingIds: string[]) => {
      if (!user?.id) return
      setStep("importing")
      setImportError(null)
      try {
        const headers = {
          ...(await supabaseBearerHeaders()),
          "Content-Type": "application/json",
        }
        const res = await fetch("/api/integrations/tradovate/import/run", {
          method: "POST",
          headers,
          body: JSON.stringify({ mappingIds }),
        })
        const data = (await res.json()) as {
          error?: string
          newTradeIds?: string[]
          totalTradesCreated?: number
        }
        if (!res.ok) {
          throw new Error(data.error ?? "Import failed.")
        }
        const ids = data.newTradeIds ?? []
        const created = data.totalTradesCreated ?? ids.length
        invalidateTradesCache(user.id)
        invalidateBrokerEnrichmentPendingCount(user.id)

        if (created === 0 || ids.length === 0) {
          setStep("caught_up")
          return
        }

        closeAll()
        queueBrokerEnrichment(ids)
      } catch (err) {
        setImportError(
          err instanceof Error ? err.message : "Could not import trades."
        )
        setStep("error")
      }
    },
    [closeAll, user?.id]
  )

  const startImportFlow = useCallback(() => {
    if (linkedAccounts.length > 1) {
      setSelectedIds(new Set(linkedAccounts.map((a) => a.mappingId)))
      setStep("select_accounts")
      return
    }
    void runImport(linkedAccounts.map((a) => a.mappingId))
  }, [linkedAccounts, runImport])

  useEffect(() => {
    if (profileLoading || !user?.id || !profile) return
    if (profileNeedsOnboarding(profile)) return
    if (!isTradovateLoginImportPromptPath(pathname ?? "")) return
    if (evaluatedRef.current) return
    if (isTradovateLoginImportDismissedThisSession()) return
    if (isWithinTradovateLoginImportPromptCooldown()) return

    evaluatedRef.current = true

    void (async () => {
      const headers = await supabaseBearerHeaders()
      const res = await fetch("/api/integrations/tradovate/import/eligibility", {
        headers,
      })
      if (!res.ok) return
      const data = (await res.json()) as {
        eligible?: boolean
        linkedAccounts?: LinkedAccount[]
      }
      if (!data.eligible || !data.linkedAccounts?.length) return

      setLinkedAccounts(data.linkedAccounts)
      markTradovateLoginImportPromptShown()
      setStep("prompt")
    })()
  }, [pathname, profile, profileLoading, user?.id])

  if (step === "closed" || !user?.id) return null

  return (
    <>
      {step === "prompt" ? (
        <ScrollableModalShell
          open
          onClose={() => {
            markTradovateLoginImportDismissedThisSession()
            void saveDontRemindIfNeeded()
            closeAll()
          }}
          ariaLabel="Import Tradovate trades"
          overlayClassName="z-[105] bg-black/60 backdrop-blur-sm"
          panelClassName="max-w-md rounded-2xl border-white/10 bg-[#152238]"
          headerClassName="shrink-0 border-b-0 px-5 pb-0 pt-5"
          bodyClassName="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-5 pt-4"
          footerClassName="shrink-0 border-t border-white/10 px-5 py-4"
          header={
            <>
              <h2 className="text-lg font-semibold text-white">Made any trades?</h2>
              <p className="mt-2 text-sm leading-relaxed text-gray-300">
                Import your latest Tradovate trades and keep your journal up to date.
              </p>
            </>
          }
          footer={
            <div className="flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-end sm:gap-3">
              <ActionButton
                type="button"
                className="min-h-[2.5rem] rounded-xl border border-white/15 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/5"
                onClick={() => {
                  markTradovateLoginImportDismissedThisSession()
                  void saveDontRemindIfNeeded()
                  closeAll()
                }}
              >
                Not now
              </ActionButton>
              <ActionButton
                type="button"
                className="min-h-[2.5rem] rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-500"
                onClick={() => startImportFlow()}
              >
                Import trades
              </ActionButton>
            </div>
          }
        >
          <TradovateImportPromptAccountCard accounts={linkedAccounts} />
          <label className="mt-5 flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              checked={dontRemind}
              onChange={(e) => setDontRemind(e.target.checked)}
              className="mt-0.5 h-4 w-4 shrink-0 rounded border-white/25 bg-white/5 text-blue-600 focus:ring-blue-500/40"
            />
            <span className="text-sm leading-snug text-gray-300">
              Don&apos;t remind me when I log in
            </span>
          </label>
        </ScrollableModalShell>
      ) : null}

      {step === "select_accounts" ? (
        <ScrollableModalShell
          open
          onClose={closeAll}
          ariaLabel="Select accounts to import"
          overlayClassName="z-[105] bg-black/60 backdrop-blur-sm"
          panelClassName="max-w-md rounded-2xl border-white/10 bg-[#152238]"
          header={
            <>
              <h2 className="text-lg font-semibold text-white">Import trades</h2>
              <p className="mt-2 text-sm text-gray-300">
                Choose which linked accounts to check for new trades.
              </p>
            </>
          }
          footer={
            <div className="flex justify-end gap-2">
              <ActionButton
                type="button"
                className="rounded-xl border border-white/15 px-4 py-2 text-sm text-gray-200"
                onClick={closeAll}
              >
                Cancel
              </ActionButton>
              <ActionButton
                type="button"
                className="rounded-xl bg-blue-600 px-4 py-2 text-sm font-semibold text-white"
                disabled={selectedIds.size === 0}
                onClick={() => void runImport([...selectedIds])}
              >
                Import trades
              </ActionButton>
            </div>
          }
        >
          <ul className="space-y-2">
            {linkedAccounts.map((acc) => {
              const checked = selectedIds.has(acc.mappingId)
              const label =
                acc.tradetraxsAccountName?.trim() ||
                acc.brokerAccountLabel ||
                "Linked account"
              return (
                <li key={acc.mappingId}>
                  <label className="flex cursor-pointer items-center gap-3 rounded-lg border border-white/10 bg-black/20 px-3 py-2">
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() => {
                        setSelectedIds((prev) => {
                          const next = new Set(prev)
                          if (next.has(acc.mappingId)) next.delete(acc.mappingId)
                          else next.add(acc.mappingId)
                          return next
                        })
                      }}
                    />
                    <span className="text-sm text-white">{label}</span>
                  </label>
                </li>
              )
            })}
          </ul>
        </ScrollableModalShell>
      ) : null}

      {step === "importing" ? (
        <ScrollableModalShell
          open
          onClose={() => {}}
          ariaLabel="Importing trades"
          overlayClassName="z-[105] bg-black/60 backdrop-blur-sm"
          panelClassName="max-w-sm rounded-2xl border-white/10 bg-[#152238]"
          showCloseButton={false}
          header={
            <h2 className="text-lg font-semibold text-white">Checking Tradovate…</h2>
          }
        >
          <p className="text-sm text-gray-400">Importing your latest trades into your journal.</p>
        </ScrollableModalShell>
      ) : null}

      {step === "caught_up" ? (
        <ScrollableModalShell
          open
          onClose={closeAll}
          ariaLabel="Import complete"
          overlayClassName="z-[105] bg-black/60 backdrop-blur-sm"
          panelClassName="max-w-sm rounded-2xl border-white/10 bg-[#152238]"
          header={
            <>
              <h2 className="text-lg font-semibold text-emerald-300">You&apos;re all caught up</h2>
              <p className="mt-2 text-sm text-gray-300">No new Tradovate trades were found.</p>
            </>
          }
          footer={
            <div className="flex justify-end">
              <ActionButton
                type="button"
                className="rounded-xl bg-blue-600 px-4 py-2 text-sm font-semibold text-white"
                onClick={closeAll}
              >
                Done
              </ActionButton>
            </div>
          }
        >
          <div />
        </ScrollableModalShell>
      ) : null}

      {step === "error" ? (
        <ScrollableModalShell
          open
          onClose={closeAll}
          ariaLabel="Import error"
          overlayClassName="z-[105] bg-black/60 backdrop-blur-sm"
          panelClassName="max-w-sm rounded-2xl border-white/10 bg-[#152238]"
          header={<h2 className="text-lg font-semibold text-red-300">Import failed</h2>}
          footer={
            <div className="flex justify-end gap-2">
              <ActionButton type="button" className="text-sm text-gray-300" onClick={closeAll}>
                Close
              </ActionButton>
              <ActionButton
                type="button"
                className="rounded-xl bg-blue-600 px-4 py-2 text-sm text-white"
                onClick={() => startImportFlow()}
              >
                Retry
              </ActionButton>
            </div>
          }
        >
          <p className="text-sm text-gray-300">{importError}</p>
        </ScrollableModalShell>
      ) : null}
    </>
  )
}
