"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react"
import {
  isDemoModeActive,
  subscribeDemoModeChanges,
} from "@/lib/demo/demoMode"
import { seedDemoCaches } from "@/lib/demo/demoUser"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import {
  registerDemoSignupHandler,
} from "@/lib/demo/requestDemoSignup"
import { TRAXPRO_TRIAL_HEADLINE } from "@/lib/traxProPricing"
import { enterSignupFlow } from "@/lib/signupFlow"

export type DemoSignupReason =
  | "default"
  | "like"
  | "comment"
  | "follow"
  | "trade"
  | "ai"
  | "upload"
  | "room"
  | "save"
  | "edit"
  | "delete"

type DemoModeContextValue = {
  isDemoMode: boolean
  userId: string | null
  requestSignup: (reason?: DemoSignupReason) => void
}

const DemoModeContext = createContext<DemoModeContextValue | null>(null)

const SIGNUP_MESSAGES: Record<DemoSignupReason, { title: string; message: string }> = {
  default: {
    title: "Start Your Free Trial",
    message:
      "Create your TradeTraxs account to track trades, connect with traders, and unlock the full platform.",
  },
  like: {
    title: "Like posts with your own account",
    message: "Sign up free to engage with the trading community.",
  },
  comment: {
    title: "Join the conversation",
    message: "Start your free trial to comment and learn from other traders.",
  },
  follow: {
    title: "Follow traders",
    message: "Create an account to follow traders and build your network.",
  },
  trade: {
    title: "Log your own trades",
    message: "Start your free trial to journal trades and track your edge.",
  },
  ai: {
    title: "Unlock AI Analyst",
    message: "Create your account to analyze your trades with AI-powered insights.",
  },
  upload: {
    title: "Share your trading journey",
    message: "Sign up to post clips, screenshots, and trade breakdowns.",
  },
  room: {
    title: "Join Trade Rooms",
    message: "Start your free trial to discuss setups and trade alongside others.",
  },
  save: {
    title: "Save to your journal",
    message: "Create an account to save trades and build your performance history.",
  },
  edit: {
    title: "Edit your trades",
    message: "Sign up to manage your own trading journal.",
  },
  delete: {
    title: "Manage your journal",
    message: "Create your account to fully control your trade history.",
  },
}

export function DemoModeProvider({ children }: { children: ReactNode }) {
  const [demoActive, setDemoActive] = useState(false)
  const [signupOpen, setSignupOpen] = useState(false)
  const [signupReason, setSignupReason] = useState<DemoSignupReason>("default")

  useEffect(() => {
    const sync = () => {
      const active = isDemoModeActive()
      setDemoActive(active)
      if (active) {
        seedDemoCaches()
      } else {
        setSignupOpen(false)
      }
    }
    sync()
    return subscribeDemoModeChanges(sync)
  }, [])

  const requestSignup = useCallback((reason: DemoSignupReason = "default") => {
    if (!isDemoModeActive()) return
    setSignupReason(reason)
    setSignupOpen(true)
  }, [])

  useEffect(() => {
    registerDemoSignupHandler(requestSignup)
    return () => registerDemoSignupHandler(null)
  }, [requestSignup])

  const value = useMemo<DemoModeContextValue>(
    () => ({
      isDemoMode: demoActive,
      userId: demoActive ? DEMO_USER_ID : null,
      requestSignup,
    }),
    [demoActive, requestSignup]
  )

  const copy = SIGNUP_MESSAGES[signupReason]

  return (
    <DemoModeContext.Provider value={value}>
      {children}
      {demoActive && signupOpen ? (
        <div
          className="fixed inset-0 z-[10000] flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          aria-labelledby="demo-signup-title"
          onClick={() => setSignupOpen(false)}
        >
          <div
            className="w-full max-w-md rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 id="demo-signup-title" className="text-xl font-semibold text-white">
              {copy.title}
            </h2>
            <p className="mt-3 text-sm leading-relaxed text-gray-400">{copy.message}</p>
            <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <button
                type="button"
                onClick={() => setSignupOpen(false)}
                className="rounded-lg border border-white/15 px-4 py-2.5 text-sm font-medium text-gray-200 hover:bg-white/5"
              >
                Keep Exploring
              </button>
              <a
                href="/login?tab=signup"
                onClick={() => enterSignupFlow()}
                className="rounded-lg bg-blue-500 px-4 py-2.5 text-center text-sm font-semibold text-white hover:bg-blue-600 disabled:hover:bg-blue-500"
              >
                Start {TRAXPRO_TRIAL_HEADLINE}
              </a>
            </div>
          </div>
        </div>
      ) : null}
    </DemoModeContext.Provider>
  )
}

export function useDemoMode(): DemoModeContextValue {
  const ctx = useContext(DemoModeContext)
  if (!ctx) {
    throw new Error("useDemoMode must be used within DemoModeProvider")
  }
  return ctx
}

export function useOptionalDemoMode(): DemoModeContextValue | null {
  return useContext(DemoModeContext)
}
