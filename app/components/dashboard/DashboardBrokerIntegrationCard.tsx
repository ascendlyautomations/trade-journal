"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import BrokerImportModalShell from "@/app/components/brokerImport/BrokerImportModalShell"
import { invalidateTradesCache } from "@/lib/appDataCache"
import { invalidateBrokerEnrichmentPendingCount } from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"
import { queueBrokerEnrichment } from "@/lib/brokerEnrichment/queueBrokerEnrichment"
import { isDemoUserId } from "@/lib/demo/constants"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

type LinkedAccount = {
  provider: "tradovate" | "rithmic"
  mappingId: string
  connectionId: string
  brokerAccountLabel: string | null
  tradetraxsAccountName: string | null
}

type Eligibility = {
  connectionCount: number
  linkedAccountCount: number
  hasSupportedConnection: boolean
  needsAccountLinking: boolean
  linkedAccounts: LinkedAccount[]
}

const cardClass =
  "tt-dash-checkin flex h-full min-h-[3.75rem] w-full min-w-0 items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2.5 text-left backdrop-blur-md transition hover:bg-white/[0.07]"

function providerLabel(provider: LinkedAccount["provider"]): string {
  return provider === "rithmic" ? "Rithmic" : "Tradovate"
}

function subtitleFor(eligibility: Eligibility | null): string {
  if (!eligibility) return "Connect Tradovate or Rithmic"
  const count = Math.max(
    eligibility.linkedAccountCount,
    eligibility.linkedAccounts.length
  )
  if (count > 0) {
    return count === 1 ? "1 account connected" : `${count} accounts connected`
  }
  if (eligibility.hasSupportedConnection || eligibility.connectionCount > 0) {
    return "Link a broker account to import trades"
  }
  return "Connect Tradovate or Rithmic"
}

export default function DashboardBrokerIntegrationCard({
  userId,
  onImportCsv,
}: {
  userId: string
  onImportCsv: () => void
}) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [eligibility, setEligibility] = useState<Eligibility | null>(null)
  const [sheetLoading, setSheetLoading] = useState(false)
  const [importingId, setImportingId] = useState<string | null>(null)
  const [sheetError, setSheetError] = useState<string | null>(null)
  const [sheetNotice, setSheetNotice] = useState<string | null>(null)

  const loadEligibility = useCallback(async () => {
    const headers = await supabaseBearerHeaders()
    const res = await fetch("/api/integrations/broker/import/eligibility", {
      headers,
    })
    if (!res.ok) throw new Error("Couldn't load broker connections.")
    const data = (await res.json()) as Partial<Eligibility>
    return {
      connectionCount: data.connectionCount ?? 0,
      linkedAccountCount: data.linkedAccountCount ?? 0,
      hasSupportedConnection: data.hasSupportedConnection === true,
      needsAccountLinking: data.needsAccountLinking === true,
      linkedAccounts: Array.isArray(data.linkedAccounts) ? data.linkedAccounts : [],
    } satisfies Eligibility
  }, [])

  useEffect(() => {
    let cancelled = false
    void loadEligibility()
      .then((next) => {
        if (!cancelled) setEligibility(next)
      })
      .catch(() => {
        if (!cancelled) setEligibility(null)
      })
    return () => {
      cancelled = true
    }
  }, [loadEligibility, userId])

  useEffect(() => {
    if (!open) return
    let cancelled = false
    setSheetLoading(true)
    setSheetError(null)
    setSheetNotice(null)
    void loadEligibility()
      .then((next) => {
        if (!cancelled) setEligibility(next)
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setSheetError(
            error instanceof Error
              ? error.message
              : "Couldn't load broker connections."
          )
        }
      })
      .finally(() => {
        if (!cancelled) setSheetLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [loadEligibility, open])

  function requireAccount() {
    if (isDemoModeActive() || isDemoUserId(userId)) {
      requestDemoSignup("save")
      return false
    }
    return true
  }

  function openSettings() {
    if (!requireAccount()) return
    setOpen(false)
    router.push("/settings#broker-integrations")
  }

  function openCsv() {
    if (!requireAccount()) return
    setOpen(false)
    onImportCsv()
  }

  async function importAccount(mappingId: string) {
    if (!requireAccount()) return
    setImportingId(mappingId)
    setSheetError(null)
    setSheetNotice(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch("/api/integrations/broker/import/run", {
        method: "POST",
        headers,
        body: JSON.stringify({ mappingIds: [mappingId] }),
      })
      const data = (await res.json()) as {
        error?: string
        newTradeIds?: string[]
        totalTradesCreated?: number
      }
      if (!res.ok) throw new Error(data.error ?? "Import failed.")
      const ids = data.newTradeIds ?? []
      const created = data.totalTradesCreated ?? ids.length
      invalidateTradesCache(userId)
      invalidateBrokerEnrichmentPendingCount(userId)
      if (created === 0 || ids.length === 0) {
        setSheetNotice("No new trades to import.")
        return
      }
      setOpen(false)
      queueBrokerEnrichment(ids)
    } catch (error) {
      setSheetError(
        error instanceof Error ? error.message : "Could not import trades."
      )
    } finally {
      setImportingId(null)
    }
  }

  const accounts = eligibility?.linkedAccounts ?? []
  const needsLink =
    accounts.length === 0 &&
    (eligibility?.needsAccountLinking === true ||
      eligibility?.hasSupportedConnection === true ||
      (eligibility?.connectionCount ?? 0) > 0)

  return (
    <div className="min-w-0">
      <button
        type="button"
        className={cardClass}
        data-testid="dashboard.brokerIntegration"
        onClick={() => {
          if (!requireAccount()) return
          setOpen(true)
        }}
      >
        <span
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-blue-500/15 text-sm text-blue-300"
          aria-hidden
        >
          <svg viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.8">
            <path d="M8.5 11.5l3-3" strokeLinecap="round" />
            <path d="M9.2 6.2l1.3-1.3a3.1 3.1 0 014.4 4.4l-1.3 1.3" strokeLinecap="round" />
            <path d="M10.8 13.8l-1.3 1.3a3.1 3.1 0 01-4.4-4.4l1.3-1.3" strokeLinecap="round" />
          </svg>
        </span>
        <span className="min-w-0 flex-1">
          <h2 className="truncate text-sm font-semibold text-white">
            Broker Integration
          </h2>
          <p className="line-clamp-2 text-xs text-gray-400">
            {subtitleFor(eligibility)}
          </p>
        </span>
        <svg
          viewBox="0 0 20 20"
          aria-hidden
          className="h-3.5 w-3.5 shrink-0 text-gray-500"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M7 5l5 5-5 5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      <BrokerImportModalShell
        open={open}
        onClose={() => {
          if (importingId) return
          setOpen(false)
        }}
        ariaLabel="Broker Integration"
        title="Broker Integration"
        closeDisabled={importingId != null}
      >
        <div className="space-y-3">
          {sheetLoading && accounts.length === 0 ? (
            <p className="text-sm text-gray-300">Loading broker connections…</p>
          ) : null}
          {sheetError ? (
            <p className="text-sm text-red-300">{sheetError}</p>
          ) : null}
          {sheetNotice ? (
            <p className="text-sm text-gray-300">{sheetNotice}</p>
          ) : null}

          {accounts.length > 0 ? (
            accounts.map((account) => {
              const title =
                account.brokerAccountLabel?.trim() ||
                account.tradetraxsAccountName?.trim() ||
                "Linked account"
              const detail = account.tradetraxsAccountName?.trim()
              const showDetail = Boolean(detail && detail !== title)
              return (
                <div
                  key={account.mappingId}
                  className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3"
                >
                  <p className="truncate text-sm font-semibold text-white" title={title}>
                    {title}
                  </p>
                  <p className="mt-0.5 truncate text-xs text-gray-400">
                    {providerLabel(account.provider)}
                    {showDetail ? ` · ${detail}` : ""}
                  </p>
                  <button
                    type="button"
                    className="mt-2 text-sm font-semibold text-blue-400 hover:text-blue-300 disabled:opacity-50"
                    disabled={importingId != null}
                    onClick={() => void importAccount(account.mappingId)}
                  >
                    {importingId === account.mappingId
                      ? "Importing…"
                      : "Import Trades"}
                  </button>
                </div>
              )
            })
          ) : needsLink ? (
            <div className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3">
              <p className="text-sm text-gray-300">
                Your broker is connected. Link a discovered account to import trades.
              </p>
              <button
                type="button"
                className="mt-2 text-sm font-semibold text-blue-400 hover:text-blue-300"
                onClick={openSettings}
              >
                Link Broker Account
              </button>
            </div>
          ) : sheetLoading ? null : (
            <div className="space-y-2">
              <button
                type="button"
                className="flex w-full items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-3 py-3 text-left"
                onClick={openSettings}
              >
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-semibold text-white">
                    Connect Broker
                  </span>
                  <span className="block text-xs text-gray-400">
                    Sync trades from Tradovate or Rithmic
                  </span>
                </span>
              </button>
              <button
                type="button"
                className="flex w-full items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-3 py-3 text-left"
                onClick={openCsv}
              >
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-semibold text-white">
                    Import CSV
                  </span>
                  <span className="block text-xs text-gray-400">
                    Upload a trade history file
                  </span>
                </span>
              </button>
            </div>
          )}
        </div>
      </BrokerImportModalShell>
    </div>
  )
}
