/**
 * Spread VU start times within a scenario to avoid synchronized RPC bursts.
 */

import { sleep } from "k6"

export function stageStartJitterSec(vuId, stageVus, maxJitterSec) {
  if (!maxJitterSec || maxJitterSec <= 0 || !stageVus || stageVus <= 0) {
    return 0
  }
  const slot = (vuId - 1) / stageVus
  const spread = slot * maxJitterSec
  const jitter = Math.random() * Math.min(2, maxJitterSec / stageVus)
  return spread + jitter
}

export function applyStageStartJitter(vuId, stageVus, maxJitterSec) {
  const delay = stageStartJitterSec(vuId, stageVus, maxJitterSec)
  if (delay > 0) {
    sleep(delay)
  }
}
