"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import UploadManager from "@/app/components/upload/UploadManager"
import type {
  TrackedUploadOptions,
  UploadJob,
  UploadProgressReporter,
} from "@/lib/uploadProgress/types"

const MAX_CONCURRENT_UPLOADS = 2
const SUCCESS_DISMISS_MS = 1400
const SESSION_EXPANDED_KEY = "tt-upload-manager-expanded"

type QueuedTask = {
  id: string
  options: TrackedUploadOptions
  resolve: () => void
  reject: (err: Error) => void
}

type UploadProgressContextValue = {
  runUpload: (options: TrackedUploadOptions) => Promise<void>
  jobs: UploadJob[]
  expanded: boolean
  setExpanded: (value: boolean) => void
}

const UploadProgressContext = createContext<UploadProgressContextValue | null>(
  null
)

export function UploadProgressProvider({ children }: { children: ReactNode }) {
  const [jobs, setJobs] = useState<UploadJob[]>([])
  const [expanded, setExpandedState] = useState(true)

  const queueRef = useRef<QueuedTask[]>([])
  const runningIdsRef = useRef<Set<string>>(new Set())
  const percentByIdRef = useRef<Map<string, number>>(new Map())
  const dismissTimersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(
    new Map()
  )
  const processQueueRef = useRef<() => void>(() => {})

  useEffect(() => {
    try {
      const stored = sessionStorage.getItem(SESSION_EXPANDED_KEY)
      if (stored === "false") setExpandedState(false)
    } catch {
      // ignore
    }
  }, [])

  const setExpanded = useCallback((value: boolean) => {
    setExpandedState(value)
    try {
      sessionStorage.setItem(SESSION_EXPANDED_KEY, String(value))
    } catch {
      // ignore
    }
  }, [])

  const patchJob = useCallback((id: string, patch: Partial<UploadJob>) => {
    setJobs((prev) =>
      prev.map((job) => (job.id === id ? { ...job, ...patch } : job))
    )
  }, [])

  const removeJob = useCallback((id: string) => {
    const timer = dismissTimersRef.current.get(id)
    if (timer) {
      clearTimeout(timer)
      dismissTimersRef.current.delete(id)
    }
    percentByIdRef.current.delete(id)
    setJobs((prev) => prev.filter((job) => job.id !== id))
  }, [])

  const finishRunningSlot = useCallback((id: string) => {
    runningIdsRef.current.delete(id)
    processQueueRef.current()
  }, [])

  const scheduleSuccessDismiss = useCallback(
    (id: string, task: QueuedTask) => {
      const timer = setTimeout(() => {
        dismissTimersRef.current.delete(id)
        removeJob(id)
        task.resolve()
        finishRunningSlot(id)
      }, SUCCESS_DISMISS_MS)
      dismissTimersRef.current.set(id, timer)
    },
    [finishRunningSlot, removeJob]
  )

  const startTask = useCallback(
    (task: QueuedTask) => {
      const { id, options } = task
      runningIdsRef.current.add(id)
      percentByIdRef.current.set(id, 0)

      patchJob(id, {
        status: "running",
        stage: "Starting…",
        percent: 0,
      })
      options.onDismissCompose?.()

      const report: UploadProgressReporter = (update) => {
        const last = percentByIdRef.current.get(id) ?? 0
        const nextPercent = Math.max(
          last,
          Math.min(99, Math.round(update.percent))
        )
        percentByIdRef.current.set(id, nextPercent)
        patchJob(id, {
          percent: nextPercent,
          stage: update.stage,
          status: "running",
        })
      }

      const runAttempt = (): Promise<void> =>
        new Promise((resolveAttempt) => {
          void (async () => {
            try {
              await options.execute(report)
              percentByIdRef.current.set(id, 100)
              patchJob(id, {
                percent: 100,
                stage: "Complete ✓",
                status: "success",
                errorMessage: undefined,
                retry: undefined,
                cancel: () => {
                  removeJob(id)
                  task.resolve()
                  finishRunningSlot(id)
                },
              })
              scheduleSuccessDismiss(id, task)
              resolveAttempt()
            } catch (err) {
              const message =
                err instanceof Error ? err.message : "Upload failed."
              const lastPercent = percentByIdRef.current.get(id) ?? 0
              patchJob(id, {
                percent: lastPercent,
                stage: "Upload failed",
                status: "error",
                errorMessage: message,
                retry: () => {
                  void runAttempt()
                },
                cancel: () => {
                  removeJob(id)
                  task.reject(new Error(message))
                  finishRunningSlot(id)
                },
              })
              finishRunningSlot(id)
              resolveAttempt()
            }
          })()
        })

      void runAttempt()
    },
    [finishRunningSlot, patchJob, removeJob, scheduleSuccessDismiss]
  )

  const processQueue = useCallback(() => {
    while (
      runningIdsRef.current.size < MAX_CONCURRENT_UPLOADS &&
      queueRef.current.length > 0
    ) {
      const task = queueRef.current.shift()
      if (task) startTask(task)
    }
  }, [startTask])

  processQueueRef.current = processQueue

  const runUpload = useCallback(
    (options: TrackedUploadOptions): Promise<void> => {
      return new Promise((resolve, reject) => {
        const id = crypto.randomUUID()
        const task: QueuedTask = { id, options, resolve, reject }
        const shouldQueue =
          runningIdsRef.current.size >= MAX_CONCURRENT_UPLOADS

        setJobs((prev) => [
          ...prev,
          {
            id,
            title: options.title,
            percent: 0,
            stage: shouldQueue ? "Queued…" : "Starting…",
            status: shouldQueue ? "queued" : "running",
          },
        ])

        if (shouldQueue) {
          queueRef.current.push(task)
        } else {
          startTask(task)
        }
      })
    },
    [startTask]
  )

  const value = useMemo(
    () => ({ runUpload, jobs, expanded, setExpanded }),
    [runUpload, jobs, expanded, setExpanded]
  )

  return (
    <UploadProgressContext.Provider value={value}>
      {children}
      <UploadManager
        jobs={jobs}
        expanded={expanded}
        onToggleExpanded={() => setExpanded(!expanded)}
      />
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
