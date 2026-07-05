"use client"

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import UploadProgressOverlay from "@/app/components/upload/UploadProgressOverlay"
import type {
  TrackedUploadOptions,
  UploadJob,
  UploadProgressReporter,
} from "@/lib/uploadProgress/types"

type UploadProgressContextValue = {
  runUpload: (options: TrackedUploadOptions) => Promise<void>
  activeJob: UploadJob | null
}

const UploadProgressContext = createContext<UploadProgressContextValue | null>(
  null
)

export function UploadProgressProvider({ children }: { children: ReactNode }) {
  const [activeJob, setActiveJob] = useState<UploadJob | null>(null)
  const dismissTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastPercentRef = useRef(0)

  const clearDismissTimer = useCallback(() => {
    if (dismissTimerRef.current) {
      clearTimeout(dismissTimerRef.current)
      dismissTimerRef.current = null
    }
  }, [])

  const dismiss = useCallback(() => {
    clearDismissTimer()
    setActiveJob(null)
    lastPercentRef.current = 0
  }, [clearDismissTimer])

  const runUpload = useCallback(
    (options: TrackedUploadOptions) => {
      const jobId = crypto.randomUUID()

      const startAttempt = (): Promise<void> =>
        new Promise((resolve, reject) => {
          lastPercentRef.current = 0

          const report: UploadProgressReporter = (update) => {
            const nextPercent = Math.max(
              lastPercentRef.current,
              Math.min(99, Math.round(update.percent))
            )
            lastPercentRef.current = nextPercent
            setActiveJob({
              id: jobId,
              title: options.title,
              percent: nextPercent,
              stage: update.stage,
              status: "running",
            })
          }

          const execute = async () => {
            setActiveJob({
              id: jobId,
              title: options.title,
              percent: 0,
              stage: "Starting…",
              status: "running",
            })
            options.onDismissCompose?.()

            try {
              await options.execute(report)
              lastPercentRef.current = 100
              setActiveJob({
                id: jobId,
                title: options.title,
                percent: 100,
                stage: "Complete ✓",
                status: "success",
                cancel: dismiss,
              })
              clearDismissTimer()
              dismissTimerRef.current = setTimeout(() => {
                dismiss()
                resolve()
              }, 1400)
            } catch (err) {
              const message =
                err instanceof Error ? err.message : "Upload failed."
              setActiveJob({
                id: jobId,
                title: options.title,
                percent: lastPercentRef.current,
                stage: "Upload failed",
                status: "error",
                errorMessage: message,
                retry: () => {
                  void startAttempt().then(resolve).catch(reject)
                },
                cancel: () => {
                  dismiss()
                  reject(new Error(message))
                },
              })
            }
          }

          void execute()
        })

      return startAttempt()
    },
    [clearDismissTimer, dismiss]
  )

  const value = useMemo(
    () => ({ runUpload, activeJob }),
    [runUpload, activeJob]
  )

  return (
    <UploadProgressContext.Provider value={value}>
      {children}
      <UploadProgressOverlay job={activeJob} onDismiss={dismiss} />
    </UploadProgressContext.Provider>
  )
}

export function useUploadProgress() {
  const ctx = useContext(UploadProgressContext)
  if (!ctx) {
    throw new Error("useUploadProgress must be used within UploadProgressProvider")
  }
  return ctx
}
