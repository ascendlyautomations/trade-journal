"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import {
  describeMicrophoneAccessFailure,
  describeRecordingSetupFailure,
  hasGetUserMediaSupport,
  isSecureRecordingContext,
  logMicrophoneAccessError,
} from "@/lib/microphoneAccess"
import {
  encodeWavBlob,
  pickMediaRecorderFormat,
  VOICE_MESSAGE_MAX_MS,
  type VoiceRecordingFormat,
} from "@/lib/voiceMessage"

export type VoiceRecorderPhase =
  | "idle"
  | "recording"
  | "denied"
  | "unsupported"

export type VoiceRecorderState = {
  phase: VoiceRecorderPhase
  elapsedMs: number
  lastError: string | null
}

type VoiceTake = {
  blob: Blob
  durationMs: number
  format: VoiceRecordingFormat
}

type UseVoiceRecorderResult = VoiceRecorderState & {
  start: () => Promise<boolean>
  cancel: () => void
  finish: () => Promise<VoiceTake | null>
  completedTake: VoiceTake | null
  consumeCompletedTake: () => void
}

type WavCapture = {
  context: AudioContext
  source: MediaStreamAudioSourceNode
  processor: ScriptProcessorNode
  stream: MediaStream
  chunks: Float32Array[]
}

const MIN_RECORDING_MS = 500
const MIN_BLOB_BYTES = 256

function stopMediaRecorder(recorder: MediaRecorder | null) {
  if (!recorder || recorder.state === "inactive") return
  try {
    if (recorder.state === "recording" && typeof recorder.requestData === "function") {
      recorder.requestData()
    }
    recorder.stop()
  } catch {
    // Ignore stop races during cleanup.
  }
}

async function startWavCapture(stream: MediaStream): Promise<WavCapture> {
  const context = new AudioContext({ sampleRate: 44_100 })
  if (context.state === "suspended") {
    await context.resume()
  }
  const source = context.createMediaStreamSource(stream)
  const processor = context.createScriptProcessor(4096, 1, 1)
  const chunks: Float32Array[] = []
  processor.onaudioprocess = (event) => {
    chunks.push(new Float32Array(event.inputBuffer.getChannelData(0)))
  }
  source.connect(processor)
  processor.connect(context.destination)
  return { context, source, processor, stream, chunks }
}

export function useVoiceRecorder(): UseVoiceRecorderResult {
  const [phase, setPhase] = useState<VoiceRecorderPhase>("idle")
  const [elapsedMs, setElapsedMs] = useState(0)
  const [lastError, setLastError] = useState<string | null>(null)
  const [completedTake, setCompletedTake] = useState<VoiceTake | null>(null)
  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const chunksRef = useRef<BlobPart[]>([])
  const streamRef = useRef<MediaStream | null>(null)
  const timerRef = useRef<number | null>(null)
  const startedAtRef = useRef<number>(0)
  const wavCaptureRef = useRef<WavCapture | null>(null)
  const formatRef = useRef<VoiceRecordingFormat | null>(null)
  const finishRef = useRef<(() => Promise<VoiceTake | null>) | null>(null)

  const cleanup = useCallback(() => {
    if (timerRef.current != null) {
      window.clearInterval(timerRef.current)
      timerRef.current = null
    }

    stopMediaRecorder(mediaRecorderRef.current)
    mediaRecorderRef.current = null
    chunksRef.current = []

    const wav = wavCaptureRef.current
    if (wav) {
      wav.processor.disconnect()
      wav.source.disconnect()
      void wav.context.close()
      wav.stream.getTracks().forEach((track) => track.stop())
      wavCaptureRef.current = null
    }

    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = null
    formatRef.current = null
  }, [])

  const finishInternal = useCallback(async (): Promise<VoiceTake | null> => {
    const startedAt = startedAtRef.current
    const durationMs = Math.min(
      VOICE_MESSAGE_MAX_MS,
      Math.max(0, Date.now() - startedAt)
    )

    if (durationMs < MIN_RECORDING_MS) {
      cleanup()
      setPhase("idle")
      setElapsedMs(0)
      setLastError("Hold the mic a little longer before sending.")
      return null
    }

    const wav = wavCaptureRef.current
    if (wav) {
      const format: VoiceRecordingFormat = {
        mimeType: "audio/wav",
        extension: "wav",
        contentType: "audio/wav",
      }
      const blob = encodeWavBlob(wav.chunks, wav.context.sampleRate)
      cleanup()
      setPhase("idle")
      setElapsedMs(0)
      if (blob.size < MIN_BLOB_BYTES) {
        setLastError(
          "No audio was captured. Try speaking closer to the microphone."
        )
        return null
      }
      const result = { blob, durationMs, format }
      setCompletedTake(result)
      setLastError(null)
      return result
    }

    const recorder = mediaRecorderRef.current
    const format = formatRef.current
    if (!recorder || !format) {
      cleanup()
      setPhase("idle")
      setElapsedMs(0)
      setLastError("Recording failed to start. Please try again.")
      return null
    }

    const blob = await new Promise<Blob>((resolve) => {
      recorder.addEventListener(
        "stop",
        () => {
          resolve(new Blob(chunksRef.current, { type: format.contentType }))
        },
        { once: true }
      )
      stopMediaRecorder(recorder)
    })

    cleanup()
    setPhase("idle")
    setElapsedMs(0)

    if (blob.size < MIN_BLOB_BYTES) {
      setLastError(
        "No audio was captured. Try speaking closer to the microphone."
      )
      return null
    }

    const result = { blob, durationMs, format }
    setCompletedTake(result)
    setLastError(null)
    return result
  }, [cleanup])

  finishRef.current = finishInternal

  useEffect(() => () => cleanup(), [cleanup])

  const start = useCallback(async () => {
    if (phase === "recording") return false
    setLastError(null)
    setCompletedTake(null)

    if (!isSecureRecordingContext()) {
      setPhase("unsupported")
      setLastError(
        "Voice recording requires a secure connection (HTTPS). Open TradeTraxs over HTTPS and try again."
      )
      return false
    }

    if (!hasGetUserMediaSupport()) {
      setPhase("unsupported")
      setLastError("Voice recording is not supported in this browser.")
      return false
    }

    let stream: MediaStream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (error) {
      logMicrophoneAccessError("getUserMedia failed", error)
      cleanup()
      const failure = describeMicrophoneAccessFailure(error)
      setPhase(failure.phase === "idle" ? "idle" : failure.phase)
      setElapsedMs(0)
      setLastError(failure.message)
      return false
    }

    streamRef.current = stream
    startedAtRef.current = Date.now()
    setElapsedMs(0)
    setPhase("recording")

    try {
      const mediaFormat = pickMediaRecorderFormat()
      let recorder: MediaRecorder | null = null
      if (mediaFormat) {
        try {
          recorder = new MediaRecorder(stream, { mimeType: mediaFormat.mimeType })
        } catch {
          recorder = null
        }
      }

      if (recorder && mediaFormat) {
        formatRef.current = mediaFormat
        mediaRecorderRef.current = recorder
        chunksRef.current = []
        recorder.ondataavailable = (event) => {
          if (event.data.size > 0) chunksRef.current.push(event.data)
        }
        recorder.start(250)
      } else {
        wavCaptureRef.current = await startWavCapture(stream)
      }
    } catch (error) {
      logMicrophoneAccessError("recorder setup failed", error)
      cleanup()
      setPhase("unsupported")
      setElapsedMs(0)
      setLastError(describeRecordingSetupFailure(error))
      return false
    }

    timerRef.current = window.setInterval(() => {
      const next = Math.min(
        VOICE_MESSAGE_MAX_MS,
        Date.now() - startedAtRef.current
      )
      setElapsedMs(next)
      if (next >= VOICE_MESSAGE_MAX_MS) {
        void finishRef.current?.()
      }
    }, 100)

    return true
  }, [cleanup, phase])

  const cancel = useCallback(() => {
    cleanup()
    setPhase("idle")
    setElapsedMs(0)
    setLastError(null)
  }, [cleanup])

  const finish = useCallback(async () => finishInternal(), [finishInternal])

  const consumeCompletedTake = useCallback(() => {
    setCompletedTake(null)
  }, [])

  return {
    phase,
    elapsedMs,
    lastError,
    start,
    cancel,
    finish,
    completedTake,
    consumeCompletedTake,
  }
}
