import type { UploadJob } from "./types"

export type GlobalUploadBarPresentation = {
  line: string
  progress: number | null
  showsRetry: boolean
  retryJobId: string | null
  activeCount: number
}

function jobProgress(job: UploadJob): number | null {
  if (job.status === "queued") return null
  if (job.status === "error") return null
  if (job.status === "success") return 1
  const raw = job.percent / 100
  if (!Number.isFinite(raw)) return null
  return Math.min(1, Math.max(0, raw))
}

export function buildGlobalUploadBarPresentation(
  jobs: UploadJob[]
): GlobalUploadBarPresentation | null {
  if (jobs.length === 0) return null

  const failures = jobs.filter((j) => j.status === "error")
  if (failures.length === 1 && jobs.length === 1) {
    const job = failures[0]!
    return {
      line: job.title,
      progress: null,
      showsRetry: Boolean(job.retry),
      retryJobId: job.retry ? job.id : null,
      activeCount: 1,
    }
  }

  if (jobs.length === 1) {
    const job = jobs[0]!
    const progress = jobProgress(job)
    return {
      line: job.status === "running" ? `${job.title} — ${job.stage}` : job.title,
      progress,
      showsRetry: job.status === "error" && Boolean(job.retry),
      retryJobId: job.status === "error" && job.retry ? job.id : null,
      activeCount: 1,
    }
  }

  const active = jobs.filter(
    (j) => j.status === "running" || j.status === "queued"
  )
  const progressSamples = active
    .map(jobProgress)
    .filter((p): p is number => p != null)
  const combined =
    progressSamples.length > 0
      ? progressSamples.reduce((a, b) => a + b, 0) / progressSamples.length
      : null

  const line =
    combined != null
      ? `Uploading ${active.length} items — ${Math.round(combined * 100)}%`
      : `Uploading ${Math.max(active.length, jobs.length)} items…`

  return {
    line,
    progress: combined,
    showsRetry: failures.length > 0,
    retryJobId: null,
    activeCount: jobs.length,
  }
}
