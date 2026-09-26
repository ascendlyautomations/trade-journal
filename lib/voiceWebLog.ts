/** Browser voice capture/upload diagnostics — console only, no PII. */

function log(message: string) {
  if (typeof console !== "undefined") {
    console.debug(message)
  }
}

export const voiceWebLog = {
  micGranted() {
    log("[VoiceWeb] micGranted")
  },

  trackState(enabled: boolean, muted: boolean, readyState: string) {
    log(
      `[VoiceWeb] trackState enabled=${enabled} muted=${muted} readyState=${readyState}`
    )
  },

  recorderStarted(mimeType: string) {
    log(`[VoiceWeb] recorderStarted mimeType=${mimeType}`)
  },

  wavCaptureStarted(sampleRate: number) {
    log(`[VoiceWeb] recorderStarted mimeType=audio/wav (ScriptProcessor) sampleRate=${sampleRate}`)
  },

  recorderStopped(chunks: number, bytes: number, mimeType: string) {
    log(
      `[VoiceWeb] recorderStopped chunks=${chunks} bytes=${bytes} mimeType=${mimeType}`
    )
  },

  localPlaybackReady(duration: number | null, peak: number | null) {
    log(
      `[VoiceWeb] localPlaybackReady duration=${duration ?? "unknown"} peak=${peak ?? "unknown"}`
    )
  },

  uploadStarted(bytes: number, mimeType: string) {
    log(`[VoiceWeb] uploadStarted bytes=${bytes} mimeType=${mimeType}`)
  },

  uploadCompleted(path: string) {
    log(`[VoiceWeb] uploadCompleted path=${path}`)
  },

  messageCreated(audioURL: string) {
    log(`[VoiceWeb] messageCreated audioURL=${audioURL}`)
  },

  captureRejected(reason: string) {
    log(`[VoiceWeb] captureRejected reason=${reason}`)
  },

  wavEncoded(fields: {
    fileBytes: number
    riffChunkSize: number
    pcmSampleCount: number
    sampleRate: number
    dataChunkBytes: number
    fmtChannels: number
    fmtBitsPerSample: number
    riffHeaderValid: boolean
    waveHeaderValid: boolean
  }) {
    log(
      `[VoiceWeb] wavEncoded fileBytes=${fields.fileBytes} riffChunkSize=${fields.riffChunkSize} ` +
        `pcmSampleCount=${fields.pcmSampleCount} sampleRate=${fields.sampleRate} ` +
        `dataChunkBytes=${fields.dataChunkBytes} fmtChannels=${fields.fmtChannels} ` +
        `fmtBitsPerSample=${fields.fmtBitsPerSample} riffHeaderValid=${fields.riffHeaderValid} ` +
        `waveHeaderValid=${fields.waveHeaderValid}`
    )
  },

  wavUploadInspect(fields: {
    fileBytes: number
    riffHeaderValid: boolean
    waveHeaderValid: boolean
    riffChunkSize?: number | null
    fmtSampleRate?: number | null
    fmtChannels?: number | null
    fmtBitsPerSample?: number | null
    dataChunkBytes?: number | null
    encodedPeak: number | null
  }) {
    log(
      `[VoiceWeb] wavUploadInspect fileBytes=${fields.fileBytes} ` +
        `riffHeaderValid=${fields.riffHeaderValid} waveHeaderValid=${fields.waveHeaderValid} ` +
        `riffChunkSize=${fields.riffChunkSize ?? "nil"} fmtSampleRate=${fields.fmtSampleRate ?? "nil"} ` +
        `fmtChannels=${fields.fmtChannels ?? "nil"} fmtBitsPerSample=${fields.fmtBitsPerSample ?? "nil"} ` +
        `dataChunkBytes=${fields.dataChunkBytes ?? "nil"} encodedPeak=${fields.encodedPeak ?? "nil"}`
    )
  },
}
