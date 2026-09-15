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
import BrokerImportModalShell, {
  BrokerImportLoadingBody,
  brokerImportFooterActionsClass,
  brokerImportPrimaryButtonClass,
  brokerImportSecondaryButtonClass,
  brokerImportGhostButtonClass,
} from "@/app/components/brokerImport/BrokerImportModalShell"
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

  const dismissPrompt = useCallback(() => {
    markTradovateLoginImportDismissedThisSession()
    void saveDontRemindIfNeeded()
    closeAll()
  }, [closeAll, saveDontRemindIfNeeded])

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
        <BrokerImportModalShell
          open
          onClose={dismissPrompt}
          ariaLabel="Import Tradovate trades"
          title="Made any trades?"
          description="Import your latest Tradovate trades and keep your journal up to date."
          footer={
            <div className={brokerImportFooterActionsClass}>
              <ActionButton
                type="button"
                className={brokerImportSecondaryButtonClass}
                onClick={dismissPrompt}
              >
                Not now
              </ActionButton>
              <ActionButton
                type="button"
                className={brokerImportPrimaryButtonClass}
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
        </BrokerImportModalShell>
      ) : null}

      {step === "select_accounts" ? (
        <BrokerImportModalShell
          open
          onClose={closeAll}
          ariaLabel="Select accounts to import"
          title="Import trades"
          description="Choose which linked accounts to check for new trades."
          footer={
            <div className={brokerImportFooterActionsClass}>
              <ActionButton
                type="button"
                className={brokerImportSecondaryButtonClass}
                onClick={closeAll}
              >
                Cancel
              </ActionButton>
              <ActionButton
                type="button"
                className={brokerImportPrimaryButtonClass}
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
                  <label className="flex cursor-pointer items-center gap-3 rounded-lg border border-white/10 bg-black/20 px-3 py-2.5">
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
                      className="h-4 w-4 shrink-0 rounded border-white/25"
                    />
                    <span className="truncate text-sm text-white">{label}</span>
                  </label>
                </li>
              )
            })}
          </ul>
        </BrokerImportModalShell>
      ) : null}

      {step === "importing" ? (
        <BrokerImportModalShell
          open
          onClose={() => {}}
          ariaLabel="Importing trades"
          title="Checking Tradovate…"
          showCloseButton={false}
          closeDisabled
        >
          <BrokerImportLoadingBody message="Looking for new trades." />
        </BrokerImportModalShell>
      ) : null}

      {step === "caught_up" ? (
        <BrokerImportModalShell
          open
          onClose={closeAll}
          ariaLabel="Import complete"
          title="You're all caught up"
          titleTone="success"
          description="No new Tradovate trades were found."
          footer={
            <div className={brokerImportFooterActionsClass}>
              <ActionButton
                type="button"
                className={brokerImportPrimaryButtonClass}
                onClick={closeAll}
              >
                Done
              </ActionButton>
            </div>
          }
        />
      ) : null}

      {step === "error" ? (
        <BrokerImportModalShell
          open
          onClose={closeAll}
          ariaLabel="Import error"
          title="Import failed"
          titleTone="error"
          description={importError ?? "Could not import trades."}
          footer={
            <div className={brokerImportFooterActionsClass}>
              <ActionButton
                type="button"
                className={brokerImportGhostButtonClass}
                onClick={closeAll}
              >
                Close
              </ActionButton>
              <ActionButton
                type="button"
                className={brokerImportPrimaryButtonClass}
                onClick={() => startImportFlow()}
              >
                Retry
              </ActionButton>
            </div>
          }
        />
      ) : null}
    </>
  )
}
