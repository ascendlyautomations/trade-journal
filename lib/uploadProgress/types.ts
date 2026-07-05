export type UploadProgressUpdate = {
  percent: number
  stage: string
}

export type UploadProgressReporter = (update: UploadProgressUpdate) => void

export type UploadJobStatus = "queued" | "running" | "success" | "error"

export type UploadJob = {
  id: string
  title: string
  percent: number
  stage: string
  status: UploadJobStatus
  errorMessage?: string
  retry?: () => void
  cancel?: () => void
}

export type TrackedUploadOptions = {
  title: string
  /** Close compose modal immediately when the upload task starts. */
  onDismissCompose?: () => void
  execute: (report: UploadProgressReporter) => Promise<void>
}

export type UploadProgressOptions = {
  onProgress?: UploadProgressReporter
}
