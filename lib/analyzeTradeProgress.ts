export type AnalyzeProgressStage = {
  percent: number
  label: string
}

export function getAnalyzeProgressStages(
  hasScreenshot: boolean
): AnalyzeProgressStage[] {
  const stages: AnalyzeProgressStage[] = [
    { percent: 0, label: "Preparing analysis..." },
    { percent: 20, label: "Reading trade details..." },
    { percent: 40, label: "Reviewing execution..." },
    { percent: 60, label: "Analyzing statistics..." },
    {
      percent: 80,
      label: hasScreenshot
        ? "Reviewing uploaded charts..."
        : "Evaluating trade context...",
    },
    { percent: 95, label: "Generating personalized coaching..." },
    { percent: 100, label: "Done" },
  ]
  return stages
}

function labelForPercent(
  stages: AnalyzeProgressStage[],
  percent: number
): string {
  let label = stages[0]?.label ?? "Preparing analysis..."
  for (const stage of stages) {
    if (percent >= stage.percent) label = stage.label
  }
  return label
}

export type AnalyzeProgressController = {
  start: () => void
  markApiComplete: () => void
  waitForCompletion: () => Promise<void>
  stop: () => void
}

/** Simulated monotonic progress — pauses near 95% until the API resolves. */
export function createAnalyzeProgressController(
  hasScreenshot: boolean,
  onUpdate: (percent: number, label: string) => void
): AnalyzeProgressController {
  const stages = getAnalyzeProgressStages(hasScreenshot)
  let percent = 0
  let apiComplete = false
  let tickId: ReturnType<typeof setInterval> | null = null
  let finishResolve: (() => void) | null = null

  function emit() {
    onUpdate(Math.round(percent), labelForPercent(stages, percent))
  }

  function start() {
    percent = 0
    apiComplete = false
    emit()

    tickId = setInterval(() => {
      const holdCap = apiComplete ? 100 : 95
      let increment = apiComplete ? 6 : 1.8

      if (!apiComplete && percent >= 88) increment = 0.35
      if (!apiComplete && percent >= 92) increment = 0.15

      const next = Math.min(holdCap, percent + increment)
      if (next > percent) {
        percent = next
        emit()
      }

      if (percent >= 100 && finishResolve) {
        const resolve = finishResolve
        finishResolve = null
        resolve()
      }
    }, 90)
  }

  function markApiComplete() {
    apiComplete = true
  }

  function waitForCompletion(): Promise<void> {
    if (percent >= 100) {
      return new Promise((resolve) => {
        setTimeout(resolve, 350)
      })
    }

    return new Promise((resolve) => {
      finishResolve = () => {
        setTimeout(resolve, 350)
      }
      if (percent >= 100) {
        finishResolve = null
        setTimeout(resolve, 350)
      }
    })
  }

  function stop() {
    if (tickId) {
      clearInterval(tickId)
      tickId = null
    }
    finishResolve = null
  }

  return { start, markApiComplete, waitForCompletion, stop }
}
