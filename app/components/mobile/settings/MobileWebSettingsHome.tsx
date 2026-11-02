"use client"

import Link from "next/link"
import {
  Bell,
  Building2,
  CircleHelp,
  CreditCard,
  FileText,
  Gift,
  Hand,
  Info,
  Link2,
  MessageSquareText,
  Palette,
  PlayCircle,
  Shield,
  Sparkles,
  Star,
  UserRound,
  Wallet,
  ChevronRight,
  Hexagon,
  LogOut,
  type LucideIcon,
} from "lucide-react"
import { useState, type ReactNode } from "react"

export type MobileWebSettingsNavItem =
  | {
      kind: "panel"
      id: string
      label: string
    }
  | {
      kind: "link"
      id: string
      label: string
      href: string
      newTab?: boolean
    }
  | {
      kind: "review"
      id: "review"
      label: string
    }
  | {
      kind: "action"
      id: string
      label: string
    }

export type MobileWebSettingsSection = {
  id: string
  title: string
  items: MobileWebSettingsNavItem[]
}

const ICONS: Record<string, LucideIcon> = {
  account: UserRound,
  profile: UserRound,
  notifications: Bell,
  privacy: Hand,
  subscription: CreditCard,
  "trading-accounts": Wallet,
  "broker-integrations": Link2,
  withdrawals: Building2,
  "prop-firm-expenses": CreditCard,
  affiliate: Gift,
  vault: Hexagon,
  appearance: Palette,
  help: CircleHelp,
  feedback: MessageSquareText,
  "whats-new": Sparkles,
  review: Star,
  terms: FileText,
  "privacy-policy": FileText,
  "community-guidelines": FileText,
  "refund-policy": FileText,
  admin: Shield,
  walkthrough: PlayCircle,
  "create-account": UserRound,
  "exit-demo": LogOut,
  about: Info,
}

type MobileWebSettingsHomeProps = {
  sections: MobileWebSettingsSection[]
  isAdmin?: boolean
  isDemo?: boolean
  onSelectPanel: (id: string) => void
  onReview: () => void
  onWalkthrough?: () => void
  onCreateAccount?: () => void
  onExitDemo?: () => void
  onSignOut: () => void
}

function RowIcon({ id, destructive }: { id: string; destructive?: boolean }) {
  const Icon = ICONS[id] ?? ChevronRight
  return (
    <Icon
      className={`h-5 w-5 ${destructive ? "text-red-400" : "text-[#4EC4E0]"}`}
      strokeWidth={1.9}
      aria-hidden
    />
  )
}

const ROW_LABEL = "min-w-0 flex-1 text-[16px] text-[color:var(--tt-text,#1f2328)]"
const CHEVRON_CLASS =
  "h-5 w-5 shrink-0 text-[color:var(--tt-text-muted,#57606a)]"

function SettingsRow({
  label,
  id,
  destructive,
  onClick,
}: {
  label: string
  id: string
  destructive?: boolean
  onClick?: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex min-h-11 w-full items-center gap-3 px-4 py-2.5 text-left"
    >
      <span className="flex h-7 w-7 shrink-0 items-center justify-center">
        <RowIcon id={id} destructive={destructive} />
      </span>
      <span
        className={`min-w-0 flex-1 text-[16px] ${
          destructive ? "text-red-400" : "text-[color:var(--tt-text,#1f2328)]"
        }`}
      >
        {label}
      </span>
      <ChevronRight className={CHEVRON_CLASS} aria-hidden />
    </button>
  )
}

export default function MobileWebSettingsHome({
  sections,
  isAdmin = false,
  isDemo = false,
  onSelectPanel,
  onReview,
  onWalkthrough,
  onCreateAccount,
  onExitDemo,
  onSignOut,
}: MobileWebSettingsHomeProps) {
  const [confirmLogout, setConfirmLogout] = useState(false)

  return (
    <div className="px-3 pb-6 pt-1">
      {isDemo ? (
        <SettingsGroup title="Demo Mode">
          <SettingsRow
            id="create-account"
            label="Create Account"
            onClick={onCreateAccount}
          />
          <Separator />
          <SettingsRow
            id="exit-demo"
            label="Exit Demo"
            destructive
            onClick={onExitDemo}
          />
        </SettingsGroup>
      ) : null}

      {isAdmin && !isDemo ? (
        <SettingsGroup title="Internal">
          <Link
            href="/admin"
            className="flex min-h-11 w-full items-center gap-3 px-4 py-2.5"
          >
            <span className="flex h-7 w-7 shrink-0 items-center justify-center">
              <RowIcon id="admin" />
            </span>
            <span className={ROW_LABEL}>Admin</span>
            <ChevronRight className={CHEVRON_CLASS} aria-hidden />
          </Link>
        </SettingsGroup>
      ) : null}

      {sections.map((section) => (
        <SettingsGroup key={section.id} title={section.title}>
          {section.items.map((item, index) => (
            <div key={item.id}>
              {index > 0 ? <Separator /> : null}
                  {item.kind === "panel" ? (
                <SettingsRow
                  id={item.id}
                  label={item.id === "affiliate" ? "Affiliate" : item.label}
                  onClick={() => onSelectPanel(item.id)}
                />
              ) : item.kind === "review" ? (
                <SettingsRow
                  id={item.id}
                  label="Leave a Rating"
                  onClick={onReview}
                />
              ) : item.kind === "action" ? (
                <SettingsRow
                  id={item.id}
                  label={item.label}
                  onClick={
                    item.id === "walkthrough" ? onWalkthrough : undefined
                  }
                />
              ) : (
                <Link
                  href={item.href}
                  target={item.newTab ? "_blank" : undefined}
                  rel={item.newTab ? "noopener noreferrer" : undefined}
                  className="flex min-h-11 w-full items-center gap-3 px-4 py-2.5"
                >
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center">
                    <RowIcon id={item.id} />
                  </span>
                  <span className={ROW_LABEL}>
                    {item.id === "withdrawals" ? "Payouts" : item.label}
                  </span>
                  <ChevronRight className={CHEVRON_CLASS} aria-hidden />
                </Link>
              )}
            </div>
          ))}
        </SettingsGroup>
      ))}

      {onWalkthrough ? (
        <SettingsGroup>
          <SettingsRow
            id="walkthrough"
            label="App Walkthrough"
            onClick={onWalkthrough}
          />
        </SettingsGroup>
      ) : null}

      {!isDemo ? (
        <SettingsGroup>
          {confirmLogout ? (
            <div className="px-4 py-3">
              <p className="text-[15px] text-[color:var(--tt-text,#1f2328)]">
                Log out of TradeTraxs?
              </p>
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={() => setConfirmLogout(false)}
                  className="min-h-11 flex-1 rounded-[14px] border border-white/15 text-[14px] font-semibold text-[color:var(--tt-text,#1f2328)]"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={onSignOut}
                  className="min-h-11 flex-1 rounded-[14px] bg-red-500/90 text-[14px] font-semibold text-white"
                >
                  Log Out
                </button>
              </div>
            </div>
          ) : (
            <SettingsRow
              id="exit-demo"
              label="Log Out"
              destructive
              onClick={() => setConfirmLogout(true)}
            />
          )}
        </SettingsGroup>
      ) : null}
    </div>
  )
}

function SettingsGroup({
  title,
  children,
}: {
  title?: string
  children: ReactNode
}) {
  return (
    <section className="mb-8">
      {title ? (
        <p className="px-4 pb-1.5 text-[13px] font-semibold text-[color:var(--tt-text-muted,#57606a)]">
          {title}
        </p>
      ) : null}
      <div className="overflow-hidden rounded-[10px] bg-white/5">{children}</div>
    </section>
  )
}

function Separator() {
  return <div className="ml-[3.25rem] h-px bg-white/10" aria-hidden />
}
