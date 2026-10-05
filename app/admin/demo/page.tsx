"use client"

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { DemoEditor, type DemoLookups } from "@/app/admin/demo/editor"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { cleanupUnusedDemoMedia, demoAdminApi, releaseDemoMedia } from "@/lib/demo/demoAdminClient"
import {
  DEMO_VIEWER_ID,
  accountName,
  blankActivity,
  blankProfile,
  blankTrade,
  cloneRecord,
  formatMoney,
  isoNow,
  mediaURL,
  moneyAmount,
  newDemoId,
  profileName,
  recordId,
  sumTradePnL,
  text,
  tradeLabel,
  type DemoAdminState,
  type DemoRecord,
} from "@/lib/demo/demoAdminModel"
import {
  accountOptionLabel,
  collectDemoMediaPaths,
  humanizeDemoIssue,
  profileOptionLabel,
  tradeOptionLabel,
} from "@/lib/demo/demoMedia"

const SECTIONS = [
  ["overview", "Overview"],
  ["profiles", "Profile"],
  ["accounts", "Accounts"],
  ["trades", "Trades"],
  ["social", "Social"],
  ["activity", "Activity"],
  ["messages", "Messages"],
  ["rooms", "Trade Rooms"],
  ["checkins", "Psychology"],
  ["payouts", "Payouts"],
  ["vault", "Vault"],
  ["history", "Versions"],
] as const

type Section = (typeof SECTIONS)[number][0]
type SocialTab = "post" | "clip" | "story" | "achievement"

type EditorState = {
  entity: string
  record: DemoRecord
  role?: string
  baseline: string
}

export default function AdminDemoPage() {
  const [allowed, setAllowed] = useState(false)
  const [checking, setChecking] = useState(true)
  const [state, setState] = useState<DemoAdminState | null>(null)
  const [section, setSection] = useState<Section>("overview")
  const [social, setSocial] = useState<SocialTab>("post")
  const [conversationID, setConversationID] = useState("")
  const [editor, setEditor] = useState<EditorState | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [validation, setValidation] = useState<string[]>([])
  const [busy, setBusy] = useState(false)
  const [confirmPublish, setConfirmPublish] = useState(false)
  const [restoreVersion, setRestoreVersion] = useState<number | null>(null)
  const [tradeQuery, setTradeQuery] = useState("")
  const [tradeAccount, setTradeAccount] = useState("")
  const [tradeSymbol, setTradeSymbol] = useState("")
  const [tradeResult, setTradeResult] = useState<"all" | "profit" | "loss">("all")
  const [tradeSort, setTradeSort] = useState<"date" | "pnl" | "symbol">("date")

  const load = useCallback(async () => {
    const next = await demoAdminApi.state()
    setState(next)
    setValidation([])
  }, [])

  useEffect(() => {
    ;(async () => {
      const check = await getCurrentAdminCheckResult()
      setAllowed(check.isAdmin)
      setChecking(false)
      if (!check.isAdmin) return
      try {
        await load()
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : "Failed to load Demo Mode")
      }
    })()
  }, [load])

  const draft = state?.draft
  const lookups = useMemo(() => buildLookups(draft), [draft])
  const editorDirty = editor != null && JSON.stringify(editor.record) !== editor.baseline

  useEffect(() => {
    if (!editorDirty) return
    const warn = (event: BeforeUnloadEvent) => {
      event.preventDefault()
    }
    window.addEventListener("beforeunload", warn)
    return () => window.removeEventListener("beforeunload", warn)
  }, [editorDirty])

  function openEditor(next: Omit<EditorState, "baseline">) {
    if (editorDirty && !window.confirm("This Demo edit has unsaved changes. Leave without saving?")) return
    setEditor({ ...next, baseline: JSON.stringify(next.record) })
  }

  function closeEditor() {
    if (editorDirty && !window.confirm("This Demo edit has unsaved changes. Leave without saving?")) return
    setEditor(null)
  }

  function accept(next: DemoAdminState) {
    if (next.ok === false && !next.draft) {
      setError(next.error || "The Demo draft could not be saved.")
      if (next.errors?.length) setValidation(next.errors.map((issue) => humanizeDemoIssue(issue, state?.draft)))
      return false
    }
    setState(next)
    setError(null)
    if (next.errors?.length) setValidation(next.errors.map((issue) => humanizeDemoIssue(issue, next.draft)))
    return true
  }

  async function run(work: () => Promise<DemoAdminState>) {
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      return accept(await work())
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Demo request failed")
      return false
    } finally {
      setBusy(false)
    }
  }

  async function saveEditor() {
    if (!editor) return
    const previousPaths = collectDemoMediaPaths(JSON.parse(editor.baseline) as DemoRecord)
    const nextPaths = new Set(collectDemoMediaPaths(editor.record))
    const ok = await run(() => demoAdminApi.save(editor.entity, editor.record, editor.role ? { role: editor.role } : {}))
    if (ok) {
      setEditor(null)
      setNotice("Saved to the draft. This is not live until you publish.")
      const released = previousPaths.filter((path) => !nextPaths.has(path))
      if (released.length) {
        try {
          await releaseDemoMedia(released)
        } catch {
          setNotice("Saved to the draft. Unused media cleanup can be retried; published versions still keep their files.")
        }
      }
    }
  }

  async function remove(entity: string, payload: DemoRecord, record?: DemoRecord) {
    const paths = record ? collectDemoMediaPaths(record) : []
    const ok = await run(() => demoAdminApi.remove(entity, payload))
    if (ok) {
      setEditor(null)
      if (paths.length) {
        try {
          await releaseDemoMedia(paths)
        } catch {
          setNotice("The Demo record was deleted. Its media stays until nothing published still uses it.")
        }
      }
    }
  }

  async function checkDraft() {
    setBusy(true)
    setError(null)
    try {
      const next = await demoAdminApi.validate()
      const errors = next.errors ?? []
      setValidation(errors.map((issue) => humanizeDemoIssue(issue, state?.draft)))
      setNotice(errors.length ? null : "The draft graph is valid.")
      if (errors.length) setError("The draft is not ready to publish.")
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Validation failed")
    } finally {
      setBusy(false)
    }
  }

  async function publish() {
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      const next = await demoAdminApi.publish()
      if (next.ok === false) {
        setValidation((next.errors ?? []).map((issue) => humanizeDemoIssue(issue, state?.draft)))
        setError("Publish was blocked. Fix the items below, then try again.")
        return
      }
      setState(next)
      setValidation([])
      setConfirmPublish(false)
      setNotice(`Published Demo version ${next.publishedVersion}. Native Demo Mode will load it on the next entry.`)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Publish failed")
    } finally {
      setBusy(false)
    }
  }

  if (checking) return <p className="p-8 text-gray-300">Checking access…</p>
  if (!allowed) return <p className="p-8 text-red-300">Admin access required.</p>

  const viewer = draft?.profiles.find((row) => row.role === "viewer")?.record

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <Link href="/admin" className="text-sm text-blue-300 hover:underline">
              ← Admin
            </Link>
            <h1 className="mt-2 text-2xl font-bold text-blue-200">Demo Mode</h1>
            <p className={`mt-2 inline-flex rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-wide ${state?.dirty ? "bg-amber-400 text-slate-950" : "bg-emerald-400 text-slate-950"}`}>
              {state?.dirty ? "Draft · Unpublished changes" : "Published · No unpublished changes"}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              className="rounded-lg border border-white/15 px-3 py-2 text-sm disabled:opacity-50"
              disabled={!state?.dirty || busy}
              onClick={() => run(demoAdminApi.discard).then((ok) => ok && setNotice("Draft reset to the published version."))}
            >
              Discard draft
            </button>
            <button
              className="rounded-lg border border-white/15 px-3 py-2 text-sm disabled:opacity-50"
              disabled={busy}
              onClick={() => {
                setBusy(true)
                setError(null)
                cleanupUnusedDemoMedia()
                  .then((count) => setNotice(count ? `Removed ${count} unused Demo file${count === 1 ? "" : "s"}.` : "No unused Demo files to remove."))
                  .catch((cause) => setError(cause instanceof Error ? cause.message : "Demo media cleanup failed."))
                  .finally(() => setBusy(false))
              }}
            >
              Clean unused media
            </button>
            <button
              className="rounded-lg border border-white/15 px-3 py-2 text-sm disabled:opacity-50"
              disabled={busy}
              onClick={checkDraft}
            >
              Check draft
            </button>
            <button
              className="rounded-lg bg-emerald-500 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
              disabled={busy || !state?.dirty}
              onClick={() => setConfirmPublish(true)}
            >
              Publish Demo
            </button>
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-3">
          <Stat label="Published version" value={state?.published ? `v${state.published.version}` : "None"} />
          <Stat label="Last published" value={formatWhen(state?.published?.publishedAt)} />
          <Stat label="Draft" value={state?.dirty ? "Unpublished changes" : "No unpublished changes"} />
        </div>

        {notice ? <p className="rounded-lg border border-emerald-400/30 bg-emerald-500/10 px-3 py-2 text-sm">{notice}</p> : null}
        {error ? <p className="rounded-lg border border-red-400/40 bg-red-500/10 px-3 py-2 text-sm text-red-100">{error}</p> : null}
        {validation.length ? (
          <div className="rounded-lg border border-amber-400/40 bg-amber-500/10 px-3 py-2 text-sm">
            <p className="font-semibold text-amber-100">Fix these before publishing</p>
            <ul className="mt-2 list-disc space-y-1 pl-5">
              {validation.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </div>
        ) : null}
        {confirmPublish ? (
          <div className="rounded-xl border border-emerald-400/30 bg-black/20 p-4">
            <p className="font-semibold">Publish Demo version {(state?.published?.version ?? 0) + 1}?</p>
            <p className="mt-1 text-sm text-gray-300">The current published version stays live until this succeeds.</p>
            <ul className="mt-3 list-disc space-y-1 pl-5 text-sm">
              {(state?.changes?.lines?.length ? state.changes.lines : ["No content differences were detected."]).map((line) => (
                <li key={line}>{line}</li>
              ))}
            </ul>
            <div className="mt-3 flex gap-2">
              <button className="rounded-lg bg-emerald-500 px-3 py-2 text-sm font-semibold" disabled={busy} onClick={publish}>
                Publish
              </button>
              <button className="rounded-lg border border-white/15 px-3 py-2 text-sm" onClick={() => setConfirmPublish(false)}>
                Cancel
              </button>
            </div>
          </div>
        ) : null}

        <div className="flex gap-2 overflow-auto pb-1">
          {SECTIONS.map(([id, label]) => (
            <button
              key={id}
              className={`shrink-0 rounded-full px-3 py-1 text-sm ${section === id ? "bg-white text-slate-900" : "bg-white/10"}`}
              onClick={() => {
                if (editorDirty && !window.confirm("This Demo edit has unsaved changes. Leave without saving?")) return
                setSection(id)
                setEditor(null)
              }}
            >
              {label}
            </button>
          ))}
        </div>

        {!draft && !error ? <p className="text-sm text-gray-300">Loading Demo draft…</p> : null}

        {section === "overview" && draft ? (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <Stat label="Demo profile" value={profileName(viewer)} />
            <Stat label="Accounts" value={String(draft.accounts.length)} />
            <Stat label="Trades" value={String(draft.trades.length)} />
            <Stat label="Derived P&L" value={formatMoney(sumTradePnL(draft.trades))} />
            <Stat label="Posts" value={String(draft.posts.length)} />
            <Stat label="Clips" value={String(draft.clips.length)} />
            <Stat label="Stories" value={String(draft.stories.length)} />
            <Stat label="Achievements" value={String(draft.achievements.length)} />
            <Stat label="Activity" value={String(draft.activity.length)} />
            <Stat label="Conversations" value={String(draft.conversations.length)} />
            <Stat label="Trade Rooms" value={String(draft.rooms.length)} />
            <Stat label="Payouts" value={String(draft.payouts.length)} />
            <Stat label="Check-ins" value={String(draft.checkIns.length)} />
            <Stat label="Vault items" value={String(draft.vaultItems.length)} />
            <Stat label="Validation" value={validation.length ? `${validation.length} issues` : "Valid"} />
            <Stat label="Published version" value={state?.published ? `v${state.published.version}` : "None"} />
            <Stat label="Draft" value={state?.dirty ? "Changed" : "Unchanged"} />
          </div>
        ) : null}

        {section === "profiles" && draft ? (
          <Manager
            title="Profiles"
            rows={draft.profiles.map((row) => ({
              key: recordId(row.record),
              title: profileName(row.record),
              detail: `@${text(row.record.username)} · ${row.role}`,
              onEdit: () => openEditor({ entity: "profile", record: cloneRecord(row.record), role: row.role }),
              onDelete:
                row.role === "peer"
                  ? () => remove("profile", { id: recordId(row.record) }, row.record)
                  : undefined,
            }))}
            onCreate={() => openEditor({ entity: "profile", record: blankProfile(), role: "peer" })}
          />
        ) : null}

        {section === "accounts" && draft ? (
          <Manager
            title="Accounts"
            rows={draft.accounts.map((row, index) => ({
              key: recordId(row),
              title: accountName(row),
              detail: `${text(row.mode)} · ${text(row.accountNumber) || "No number"} · ${formatMoney(moneyAmount(row, "size"))}`,
              onEdit: () => openEditor({ entity: "account", record: cloneRecord(row) }),
              onDelete: () => remove("account", { id: recordId(row) }),
              onUp: index > 0 ? () => move("account", draft.accounts, index, -1, run) : undefined,
              onDown: index < draft.accounts.length - 1 ? () => move("account", draft.accounts, index, 1, run) : undefined,
            }))}
            onCreate={() =>
              openEditor({
                entity: "account",
                record: {
                  id: newDemoId("account"),
                  ownerProfileID: DEMO_VIEWER_ID,
                  name: "New account",
                  category: "propFirm",
                  mode: "evaluation",
                  size: { amount: 50000, currencyCode: "USD" },
                  isActive: true,
                  canAddTrades: true,
                  showInAccountDropdowns: true,
                },
              })
            }
          />
        ) : null}

        {section === "trades" && draft ? (
          <TradeBrowser
            draft={draft}
            query={tradeQuery}
            accountID={tradeAccount}
            symbol={tradeSymbol}
            result={tradeResult}
            sort={tradeSort}
            onQuery={setTradeQuery}
            onAccount={setTradeAccount}
            onSymbol={setTradeSymbol}
            onResult={setTradeResult}
            onSort={setTradeSort}
            onEdit={(row) => openEditor({ entity: "trade", record: cloneRecord(row) })}
            onDelete={(row) => remove("trade", { id: recordId(row) }, row)}
            onCreate={() => openEditor({ entity: "trade", record: blankTrade(recordId(draft.accounts[0])) })}
          />
        ) : null}

        {section === "social" && draft ? (
          <div className="space-y-4">
            <div className="flex gap-2">
              {(["post", "clip", "story", "achievement"] as SocialTab[]).map((tab) => (
                <button key={tab} className={`rounded-full px-3 py-1 text-sm ${social === tab ? "bg-white text-slate-900" : "bg-white/10"}`} onClick={() => setSocial(tab)}>
                  {tab === "post" ? "Posts" : tab === "clip" ? "Clips" : tab === "story" ? "Stories" : "Achievements"}
                </button>
              ))}
            </div>
            <SocialList tab={social} draft={draft} setEditor={openEditor} remove={remove} run={run} />
          </div>
        ) : null}

        {section === "activity" && draft ? (
          <Manager
            title="Activity"
            rows={draft.activity.map((row) => ({
              key: recordId(row),
              title: `${text(row.kind)} · ${profileName(findProfile(draft, text(row.actorProfileID)))}`,
              detail: text(row.tradeID) ? tradeLabel(draft.trades.find((trade) => recordId(trade) === text(row.tradeID))) : text(row.body),
              onEdit: () => openEditor({ entity: "activity", record: cloneRecord(row) }),
              onDelete: () => remove("activity", { id: recordId(row) }),
            }))}
            onCreate={() =>
              openEditor({
                entity: "activity",
                record: blankActivity(recordId(draft.profiles.find((row) => row.role === "peer")?.record), recordId(draft.trades[0])),
              })
            }
          />
        ) : null}

        {section === "messages" && draft ? (
          <div className="grid gap-4 lg:grid-cols-[16rem_1fr]">
            <div className="space-y-2">
              {draft.conversations.map((row) => (
                <button
                  key={recordId(row)}
                  className={`block w-full rounded-lg border px-3 py-2 text-left text-sm ${conversationID === recordId(row) ? "border-emerald-400/50 bg-emerald-500/10" : "border-white/10 bg-white/5"}`}
                  onClick={() => setConversationID(recordId(row))}
                >
                  {text(row.title) || "Conversation"}
                </button>
              ))}
              <button
                className="text-sm text-emerald-300"
                onClick={() =>
                  openEditor({
                    entity: "conversation",
                    record: {
                      id: newDemoId("dm"),
                      title: "New conversation",
                      isGroup: false,
                      isMuted: false,
                      isPinned: false,
                      unreadCount: 0,
                      updatedAt: isoNow(),
                      participantProfileIDs: [DEMO_VIEWER_ID],
                    },
                  })
                }
              >
                New conversation
              </button>
            </div>
            <ConversationPane
              draft={draft}
              conversationID={conversationID}
              setEditor={openEditor}
              remove={remove}
            />
          </div>
        ) : null}

        {section === "rooms" && draft ? <RoomSection draft={draft} setEditor={openEditor} remove={remove} /> : null}

        {section === "checkins" && draft ? (
          <Manager
            title="Daily check-ins"
            rows={draft.checkIns.map((row) => ({
              key: recordId(row),
              title: text(row.checkInDate),
              detail: `Stress ${text(row.stressLevel)} · Sleep ${text(row.sleepHours)}h`,
              onEdit: () => openEditor({ entity: "check_in", record: cloneRecord(row) }),
              onDelete: () => remove("check_in", { id: recordId(row) }),
            }))}
            onCreate={() =>
              openEditor({
                entity: "check_in",
                record: {
                  id: newDemoId("checkin"),
                  ownerProfileID: DEMO_VIEWER_ID,
                  checkInDate: new Date().toISOString().slice(0, 10),
                  sleepHours: 7,
                  sleepQuality: 4,
                  morningRating: 4,
                  stressLevel: 2,
                  energyLevel: 4,
                  focusLevel: 4,
                  notes: "",
                  createdAt: isoNow(),
                  updatedAt: isoNow(),
                },
              })
            }
          />
        ) : null}

        {section === "payouts" && draft ? (
          <Manager
            title="Payouts"
            rows={draft.payouts.map((row) => ({
              key: recordId(row),
              title: formatMoney(moneyAmount(row, "amount")),
              detail: accountName(draft.accounts.find((account) => recordId(account) === text(row.accountID))),
              onEdit: () => openEditor({ entity: "payout", record: cloneRecord(row) }),
              onDelete: () => remove("payout", { id: recordId(row) }, row),
            }))}
            onCreate={() =>
              openEditor({
                entity: "payout",
                record: {
                  id: newDemoId("payout"),
                  accountID: recordId(draft.accounts[0]),
                  amount: { amount: 0, currencyCode: "USD" },
                  payoutDate: isoNow(),
                  note: "",
                },
              })
            }
          />
        ) : null}

        {section === "vault" && draft ? (
          <div className="space-y-6">
            <Manager
              title="Folders"
              rows={draft.vaultFolders.map((row, index) => ({
                key: recordId(row),
                title: text(row.name),
                detail: "",
                onEdit: () => openEditor({ entity: "vault_folder", record: cloneRecord(row) }),
                onDelete: () => remove("vault_folder", { id: recordId(row) }),
                onUp: index > 0 ? () => move("vault_folder", draft.vaultFolders, index, -1, run) : undefined,
                onDown: index < draft.vaultFolders.length - 1 ? () => move("vault_folder", draft.vaultFolders, index, 1, run) : undefined,
              }))}
              onCreate={() =>
                openEditor({
                  entity: "vault_folder",
                  record: { id: newDemoId("vault"), name: "New folder", createdAt: isoNow(), updatedAt: isoNow() },
                })
              }
            />
            <Manager
              title="Saved items"
              rows={draft.vaultItems.map((row, index) => ({
                key: recordId(row),
                title: vaultLabel(row, draft),
                detail: "",
                onEdit: () => openEditor({ entity: "vault_item", record: cloneRecord(row) }),
                onDelete: () => remove("vault_item", { id: recordId(row) }),
                onUp: index > 0 ? () => move("vault_item", draft.vaultItems, index, -1, run) : undefined,
                onDown: index < draft.vaultItems.length - 1 ? () => move("vault_item", draft.vaultItems, index, 1, run) : undefined,
              }))}
              onCreate={() =>
                openEditor({
                  entity: "vault_item",
                  record: {
                    id: newDemoId("vault.item"),
                    ref: { contentType: "trade", contentID: recordId(draft.trades[0]) },
                    folderIDs: draft.vaultFolders[0] ? [recordId(draft.vaultFolders[0])] : [],
                    createdAt: isoNow(),
                  },
                })
              }
            />
          </div>
        ) : null}

        {section === "history" && state ? (
          <div className="space-y-2">
            {state.history.map((version) => (
              <div key={version.version} className={`rounded-xl border px-4 py-3 ${version.isCurrent ? "border-emerald-400/40 bg-emerald-500/10" : "border-white/10 bg-white/5"}`}>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p className="font-semibold">
                      Version {version.version}
                      {version.isCurrent ? " · Current" : ""}
                    </p>
                    <p className="text-xs text-gray-400">
                      {formatWhen(version.publishedAt)}
                      {version.publisherEmail ? ` · ${version.publisherEmail}` : ""}
                    </p>
                  </div>
                  {version.isCurrent ? (
                    <span className="rounded-full bg-emerald-400 px-2 py-0.5 text-xs font-semibold text-slate-950">Current</span>
                  ) : (
                    <button
                      className="rounded-lg border border-white/15 px-3 py-1.5 text-sm"
                      disabled={busy}
                      onClick={() => setRestoreVersion(version.version)}
                    >
                      Restore
                    </button>
                  )}
                </div>
                {version.changeSummary?.lines?.length ? (
                  <ul className="mt-2 list-disc pl-5 text-xs text-gray-300">
                    {version.changeSummary.lines.map((line) => (
                      <li key={line}>{line}</li>
                    ))}
                  </ul>
                ) : (
                  <p className="mt-2 text-xs text-gray-500">No stored change summary.</p>
                )}
                {restoreVersion === version.version ? (
                  <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
                    <span>Republish version {version.version} as a new version?</span>
                    <button
                      className="rounded-lg bg-emerald-500 px-3 py-1.5 text-sm font-semibold"
                      disabled={busy}
                      onClick={() =>
                        run(() => demoAdminApi.restore(version.version)).then((ok) => {
                          if (ok) {
                            setRestoreVersion(null)
                            setNotice(`Restored version ${version.version} as a new published version. Re-enter Demo Mode to see it.`)
                          }
                        })
                      }
                    >
                      Restore
                    </button>
                    <button className="text-gray-300" onClick={() => setRestoreVersion(null)}>
                      Cancel
                    </button>
                  </div>
                ) : null}
              </div>
            ))}
          </div>
        ) : null}

        {editor && lookups ? (
          <section className="rounded-xl border border-white/10 bg-black/20 p-4">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="font-semibold capitalize">{editor.entity.replaceAll("_", " ")}</h2>
              <button className="text-sm text-gray-400" onClick={closeEditor}>
                Close
              </button>
            </div>
            <DemoEditor
              entity={editor.entity}
              record={editor.record}
              role={editor.role}
              lookups={lookups}
              onChange={(record) => setEditor({ ...editor, record })}
              onRole={(role) => setEditor({ ...editor, role })}
            />
            <button className="mt-4 rounded-lg bg-emerald-500 px-3 py-2 text-sm font-semibold disabled:opacity-50" disabled={busy} onClick={saveEditor}>
              Save draft
            </button>
          </section>
        ) : null}
      </div>
    </div>
  )
}

function SocialList({
  tab,
  draft,
  setEditor,
  remove,
  run,
}: {
  tab: SocialTab
  draft: DemoAdminState["draft"]
  setEditor: (editor: Omit<EditorState, "baseline">) => void
  remove: (entity: string, payload: DemoRecord, record?: DemoRecord) => void
  run: (work: () => Promise<DemoAdminState>) => Promise<boolean>
}) {
  const openEditor = setEditor
  const rows =
    tab === "post" ? draft.posts : tab === "clip" ? draft.clips : tab === "story" ? draft.stories : draft.achievements
  return (
    <Manager
      title={tab}
      rows={rows.map((row, index) => ({
        key: recordId(row),
        title: tab === "achievement" ? text(row.title) : tab === "clip" ? text(row.caption) || "Clip" : tab === "story" ? profileName(findProfile(draft, text(row.authorProfileID))) : text(row.body),
        detail: tab === "clip" && mediaURL(row.video) ? "Video attached" : tradeLabel(draft.trades.find((trade) => recordId(trade) === text(row.linkedTradeID))),
        onEdit: () => openEditor({ entity: tab, record: cloneRecord(row) }),
        onDelete: () => remove(tab, { id: recordId(row) }, row),
        onUp: tab !== "story" && index > 0 ? () => move(tab, rows, index, -1, run) : undefined,
        onDown: tab !== "story" && index < rows.length - 1 ? () => move(tab, rows, index, 1, run) : undefined,
      }))}
      onCreate={() => openEditor({ entity: tab, record: blankSocial(tab, draft) })}
    />
  )
}

function ConversationPane({
  draft,
  conversationID,
  setEditor,
  remove,
}: {
  draft: DemoAdminState["draft"]
  conversationID: string
  setEditor: (editor: Omit<EditorState, "baseline">) => void
  remove: (entity: string, payload: DemoRecord, record?: DemoRecord) => void
}) {
  const openEditor = setEditor
  const conversation = draft.conversations.find((row) => recordId(row) === conversationID)
  const messages = draft.messages.filter((row) => text(row.conversationID) === conversationID)
  if (!conversation) return <p className="text-sm text-gray-400">Choose a conversation.</p>
  return (
    <div className="space-y-3">
      <div className="flex justify-between">
        <h2 className="font-semibold">{text(conversation.title)}</h2>
        <button className="text-sm text-blue-300" onClick={() => openEditor({ entity: "conversation", record: cloneRecord(conversation) })}>
          Edit participants
        </button>
      </div>
      {messages.map((row) => (
        <div key={recordId(row)} className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
          <p className="text-xs text-gray-400">{profileName(findProfile(draft, text(row.senderProfileID)))}</p>
          <p className="text-sm">{text(row.body)}</p>
          <div className="mt-2 flex gap-3 text-xs">
            <button className="text-blue-300" onClick={() => openEditor({ entity: "message", record: cloneRecord(row) })}>
              Edit
            </button>
            <button className="text-red-300" onClick={() => remove("message", { id: recordId(row) }, row)}>
              Delete
            </button>
          </div>
        </div>
      ))}
      <button
        className="text-sm text-emerald-300"
        onClick={() =>
          openEditor({
            entity: "message",
            record: {
              id: newDemoId("message"),
              conversationID,
              senderProfileID: DEMO_VIEWER_ID,
              body: "",
              kind: "text",
              createdAt: isoNow(),
              attachments: [],
              roomReactions: [],
              isReadByViewer: true,
            },
          })
        }
      >
        Add message
      </button>
    </div>
  )
}

function RoomSection({
  draft,
  setEditor,
  remove,
}: {
  draft: DemoAdminState["draft"]
  setEditor: (editor: Omit<EditorState, "baseline">) => void
  remove: (entity: string, payload: DemoRecord, record?: DemoRecord) => void
}) {
  const openEditor = setEditor
  const room = draft.rooms[0]
  if (!room) {
    return (
      <button
        className="rounded-lg bg-emerald-500 px-3 py-2 text-sm font-semibold"
        onClick={() =>
          openEditor({
            entity: "room",
            record: {
              id: newDemoId("room"),
              name: "TradeTraxs Traders",
              slug: "tradetraxs-traders",
              description: "",
              discoveryTags: [],
              ownerProfileID: DEMO_VIEWER_ID,
              createdAt: isoNow(),
              isPrivate: false,
              joinPolicy: "open",
              roomKind: "community",
              category: "day_trading",
              memberCount: 0,
              showsOnProfile: true,
              membersCanMessage: true,
              membersCanShareMedia: true,
              membersCanShareTrades: true,
            },
          })
        }
      >
        Create room
      </button>
    )
  }
  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
        <h2 className="text-lg font-semibold">{text(room.name)}</h2>
        <p className="mt-1 text-sm text-gray-300">{text(room.description)}</p>
        <button className="mt-3 text-sm text-blue-300" onClick={() => openEditor({ entity: "room", record: cloneRecord(room) })}>
          Edit room
        </button>
      </div>
      <Manager
        title="Members"
        rows={draft.memberships.map((row) => ({
          key: `${text(row.roomID)}:${text(row.profileID)}`,
          title: profileName(findProfile(draft, text(row.profileID))),
          detail: text(row.role),
          onEdit: () => openEditor({ entity: "membership", record: cloneRecord(row) }),
          onDelete: text(row.role) === "owner" ? undefined : () => remove("membership", { roomID: text(row.roomID), profileID: text(row.profileID) }),
        }))}
        onCreate={() =>
          openEditor({
            entity: "membership",
            record: {
              roomID: recordId(room),
              profileID: "",
              role: "member",
              joinedAt: isoNow(),
              notificationsEnabled: true,
            },
          })
        }
      />
      <Manager
        title="Room messages"
        rows={draft.roomMessages.map((row) => ({
          key: recordId(row),
          title: profileName(findProfile(draft, text(row.senderProfileID))),
          detail: text(row.body),
          onEdit: () => openEditor({ entity: "room_message", record: cloneRecord(row) }),
          onDelete: () => remove("room_message", { id: recordId(row) }, row),
        }))}
        onCreate={() =>
          openEditor({
            entity: "room_message",
            record: {
              id: newDemoId("room-message"),
              roomID: recordId(room),
              channelID: recordId(draft.channels[0]) || null,
              senderProfileID: DEMO_VIEWER_ID,
              body: "",
              media: [],
              reactions: [],
              isPinned: false,
              createdAt: isoNow(),
            },
          })
        }
      />
    </div>
  )
}

function TradeBrowser({
  draft,
  query,
  accountID,
  symbol,
  result,
  sort,
  onQuery,
  onAccount,
  onSymbol,
  onResult,
  onSort,
  onEdit,
  onDelete,
  onCreate,
}: {
  draft: DemoAdminState["draft"]
  query: string
  accountID: string
  symbol: string
  result: "all" | "profit" | "loss"
  sort: "date" | "pnl" | "symbol"
  onQuery: (value: string) => void
  onAccount: (value: string) => void
  onSymbol: (value: string) => void
  onResult: (value: "all" | "profit" | "loss") => void
  onSort: (value: "date" | "pnl" | "symbol") => void
  onEdit: (row: DemoRecord) => void
  onDelete: (row: DemoRecord) => void
  onCreate: () => void
}) {
  const symbols = [...new Set(draft.trades.map((row) => text(row.symbol && typeof row.symbol === "object" ? (row.symbol as DemoRecord).ticker : "")))].filter(Boolean)
  const needle = query.trim().toLowerCase()
  const rows = draft.trades
    .filter((row) => {
      const account = accountName(draft.accounts.find((item) => recordId(item) === text(row.accountID)))
      const ticker = text(row.symbol && typeof row.symbol === "object" ? (row.symbol as DemoRecord).ticker : "")
      const pnl = moneyAmount(row) ?? 0
      if (accountID && text(row.accountID) !== accountID) return false
      if (symbol && ticker !== symbol) return false
      if (result === "profit" && pnl <= 0) return false
      if (result === "loss" && pnl >= 0) return false
      if (!needle) return true
      return `${ticker} ${account} ${text(row.side)} ${text(row.visibility)}`.toLowerCase().includes(needle)
    })
    .sort((left, right) => {
      if (sort === "pnl") return (moneyAmount(right) ?? 0) - (moneyAmount(left) ?? 0)
      if (sort === "symbol") return text(left.symbol && typeof left.symbol === "object" ? (left.symbol as DemoRecord).ticker : "").localeCompare(text(right.symbol && typeof right.symbol === "object" ? (right.symbol as DemoRecord).ticker : ""))
      return text(right.entryAt).localeCompare(text(left.entryAt))
    })
  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-semibold">Trades</h2>
        <button className="rounded-lg bg-emerald-500 px-3 py-1.5 text-sm font-semibold" onClick={onCreate}>
          Create trade
        </button>
      </div>
      <div className="grid gap-2 md:grid-cols-5">
        <input className="rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm" placeholder="Search" value={query} onChange={(event) => onQuery(event.target.value)} />
        <select className="rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm" value={accountID} onChange={(event) => onAccount(event.target.value)}>
          <option value="">All accounts</option>
          {draft.accounts.map((account) => (
            <option key={recordId(account)} value={recordId(account)}>{accountOptionLabel(account)}</option>
          ))}
        </select>
        <select className="rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm" value={symbol} onChange={(event) => onSymbol(event.target.value)}>
          <option value="">All symbols</option>
          {symbols.map((item) => (
            <option key={item} value={item}>{item}</option>
          ))}
        </select>
        <select className="rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm" value={result} onChange={(event) => onResult(event.target.value as "all" | "profit" | "loss")}>
          <option value="all">Profit and loss</option>
          <option value="profit">Profitable</option>
          <option value="loss">Losing</option>
        </select>
        <select className="rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm" value={sort} onChange={(event) => onSort(event.target.value as "date" | "pnl" | "symbol")}>
          <option value="date">Date</option>
          <option value="pnl">P&L</option>
          <option value="symbol">Symbol</option>
        </select>
      </div>
      {!rows.length ? <p className="text-sm text-gray-400">No trades match these filters.</p> : null}
      <div className="overflow-x-auto rounded-xl border border-white/10">
        <table className="w-full min-w-[720px] text-left text-sm">
          <thead className="text-xs uppercase text-gray-400">
            <tr>
              <th className="px-3 py-2">Date</th>
              <th className="px-3 py-2">Account</th>
              <th className="px-3 py-2">Symbol</th>
              <th className="px-3 py-2">Side</th>
              <th className="px-3 py-2">P&L</th>
              <th className="px-3 py-2">Visibility</th>
              <th className="px-3 py-2" />
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={recordId(row)} className="border-t border-white/10">
                <td className="px-3 py-2">{text(row.entryAt).slice(0, 10)}</td>
                <td className="px-3 py-2">{accountOptionLabel(draft.accounts.find((account) => recordId(account) === text(row.accountID)))}</td>
                <td className="px-3 py-2">{text(row.symbol && typeof row.symbol === "object" ? (row.symbol as DemoRecord).ticker : "")}</td>
                <td className="px-3 py-2 capitalize">{text(row.side)}</td>
                <td className="px-3 py-2">{formatMoney(moneyAmount(row))}</td>
                <td className="px-3 py-2 capitalize">{text(row.visibility)}</td>
                <td className="px-3 py-2 text-right">
                  <button className="text-blue-300" onClick={() => onEdit(row)}>Edit</button>
                  <button className="ml-3 text-red-300" onClick={() => onDelete(row)}>Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function Manager({
  title,
  rows,
  onCreate,
}: {
  title: string
  rows: Array<{
    key: string
    title: string
    detail: string
    onEdit: () => void
    onDelete?: () => void
    onUp?: () => void
    onDown?: () => void
  }>
  onCreate: () => void
}) {
  const [query, setQuery] = useState("")
  const needle = query.trim().toLowerCase()
  const visible = rows.filter((row) => !needle || `${row.title} ${row.detail}`.toLowerCase().includes(needle))
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-semibold capitalize">{title}</h2>
        <button className="rounded-lg bg-emerald-500 px-3 py-1.5 text-sm font-semibold" onClick={onCreate}>
          Create
        </button>
      </div>
      <input
        className="w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm"
        placeholder={`Search ${title}`}
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      {!visible.length ? <p className="text-sm text-gray-400">Nothing in this list yet.</p> : null}
      {visible.map((row) => (
        <div key={row.key} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/5 px-4 py-3">
          <div>
            <p className="font-medium">{row.title || "Untitled"}</p>
            {row.detail ? <p className="text-xs text-gray-400">{row.detail}</p> : null}
          </div>
          <div className="flex gap-3 text-sm">
            {row.onUp ? <button onClick={row.onUp}>Up</button> : null}
            {row.onDown ? <button onClick={row.onDown}>Down</button> : null}
            <button className="text-blue-300" onClick={row.onEdit}>
              Edit
            </button>
            {row.onDelete ? (
              <button className="text-red-300" onClick={row.onDelete}>
                Delete
              </button>
            ) : null}
          </div>
        </div>
      ))}
    </section>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-4">
      <p className="text-xs uppercase tracking-wide text-gray-400">{label}</p>
      <p className="mt-1 text-lg font-semibold">{value}</p>
    </div>
  )
}

function buildLookups(draft: DemoAdminState["draft"] | undefined): DemoLookups {
  if (!draft) {
    return { profiles: [], accounts: [], trades: [], posts: [], clips: [], achievements: [], conversations: [], rooms: [], channels: [], folders: [] }
  }
  return {
    profiles: draft.profiles.map((row) => ({ id: recordId(row.record), label: profileOptionLabel(row.record) })),
    accounts: draft.accounts.map((row) => ({ id: recordId(row), label: accountOptionLabel(row) })),
    trades: draft.trades.map((row) => ({
      id: recordId(row),
      label: tradeOptionLabel(row, accountName(draft.accounts.find((account) => recordId(account) === text(row.accountID)))),
    })),
    posts: draft.posts.map((row) => ({ id: recordId(row), label: text(row.body).slice(0, 60) || recordId(row) })),
    clips: draft.clips.map((row) => ({ id: recordId(row), label: text(row.caption) || recordId(row) })),
    achievements: draft.achievements.map((row) => ({ id: recordId(row), label: text(row.title) || recordId(row) })),
    conversations: draft.conversations.map((row) => ({ id: recordId(row), label: text(row.title) || recordId(row) })),
    rooms: draft.rooms.map((row) => ({ id: recordId(row), label: text(row.name) || recordId(row) })),
    channels: draft.channels.map((row) => ({ id: recordId(row), label: text(row.name) || recordId(row) })),
    folders: draft.vaultFolders.map((row) => ({ id: recordId(row), label: text(row.name) || recordId(row) })),
  }
}

function findProfile(draft: DemoAdminState["draft"], id: string) {
  return draft.profiles.find((row) => recordId(row.record) === id)?.record
}

function vaultLabel(row: DemoRecord, draft: DemoAdminState["draft"]) {
  const ref = row.ref && typeof row.ref === "object" ? (row.ref as DemoRecord) : {}
  const id = text(ref.contentID)
  if (ref.contentType === "trade") return tradeLabel(draft.trades.find((trade) => recordId(trade) === id))
  if (ref.contentType === "achievement") return text(draft.achievements.find((item) => recordId(item) === id)?.title)
  if (ref.contentType === "reel") return text(draft.clips.find((item) => recordId(item) === id)?.caption)
  return text(draft.posts.find((item) => recordId(item) === id)?.body).slice(0, 60)
}

function blankSocial(tab: SocialTab, draft: DemoAdminState["draft"]): DemoRecord {
  const author = DEMO_VIEWER_ID
  const now = isoNow()
  if (tab === "post") {
    return { id: newDemoId("post"), authorProfileID: author, body: "", media: [], visibility: "public", createdAt: now, updatedAt: now, isPinned: false }
  }
  if (tab === "clip") {
    return {
      id: newDemoId("clip"),
      authorProfileID: author,
      caption: "",
      visibility: "public",
      createdAt: now,
      durationSeconds: 10,
      video: { id: "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80", kind: "video", altText: "Clip" },
    }
  }
  if (tab === "story") {
    return {
      id: newDemoId("story"),
      authorProfileID: author,
      createdAt: now,
      expiresAt: new Date(Date.now() + 86400000).toISOString(),
      viewerHasSeen: false,
      media: { id: "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80", kind: "image", altText: "Story" },
    }
  }
  return {
    id: newDemoId("achievement"),
    ownerProfileID: author,
    accountID: recordId(draft.accounts[0]) || null,
    title: "New achievement",
    description: "",
    kind: "prop_firm_payout",
    tier: "gold",
    isPublic: true,
    isFeatured: false,
    achievedAt: now,
    sortOrder: draft.achievements.length,
  }
}

async function move(
  entity: string,
  rows: DemoRecord[],
  index: number,
  direction: number,
  run: (work: () => Promise<DemoAdminState>) => Promise<boolean>
) {
  const ids = rows.map(recordId)
  const target = index + direction
  ;[ids[index], ids[target]] = [ids[target], ids[index]]
  await run(() => demoAdminApi.reorder(entity, ids))
}

function formatWhen(value: string | null | undefined) {
  if (!value) return "—"
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return date.toLocaleString()
}
