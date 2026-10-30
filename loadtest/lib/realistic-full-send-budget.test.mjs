/**
 * Contract: global send cap partitioning for realistic600_full and realistic1000_full.
 */
import assert from "node:assert/strict"
import { describe, it } from "node:test"

function vuAllowanceFromGlobalPartition(globalCap, maxVus, vuIdInTest) {
  const cap = Math.max(0, Math.floor(globalCap))
  const vus = Math.max(1, Math.floor(maxVus))
  const vu = Math.max(1, Math.min(vuIdInTest, vus))
  const base = Math.floor(cap / vus)
  const remainder = cap % vus
  return base + (vu <= remainder ? 1 : 0)
}

function partitionSum(globalCap, maxVus) {
  let sum = 0
  for (let vu = 1; vu <= maxVus; vu++) {
    sum += vuAllowanceFromGlobalPartition(globalCap, maxVus, vu)
  }
  return sum
}

describe("realistic full send budget partition", () => {
  it("sums to global cap for 600 VUs and 400 sends", () => {
    assert.equal(partitionSum(400, 600), 400)
    assert.equal(vuAllowanceFromGlobalPartition(400, 600, 1), 1)
    assert.equal(vuAllowanceFromGlobalPartition(400, 600, 400), 1)
    assert.equal(vuAllowanceFromGlobalPartition(400, 600, 401), 0)
    assert.equal(vuAllowanceFromGlobalPartition(400, 600, 600), 0)
  })

  it("sums to global cap for 1000 VUs and 700 sends (realistic1000_full)", () => {
    assert.equal(partitionSum(700, 1000), 700)
    assert.equal(vuAllowanceFromGlobalPartition(700, 1000, 1), 1)
    assert.equal(vuAllowanceFromGlobalPartition(700, 1000, 700), 1)
    assert.equal(vuAllowanceFromGlobalPartition(700, 1000, 701), 0)
    assert.equal(vuAllowanceFromGlobalPartition(700, 1000, 1000), 0)
    let vusWithAllowance = 0
    for (let vu = 1; vu <= 1000; vu++) {
      if (vuAllowanceFromGlobalPartition(700, 1000, vu) > 0) {
        vusWithAllowance++
      }
    }
    assert.equal(vusWithAllowance, 700)
  })

  it("maps 1000 VUs to 100 accounts at 10 VUs each (even split)", () => {
    const maxVus = 1000
    const userCount = 100
    const perUser = maxVus / userCount
    const indices = []
    for (let u = 0; u < userCount; u++) {
      for (let k = 0; k < perUser; k++) {
        indices.push(u)
      }
    }
    assert.equal(indices.length, maxVus)
    const counts = new Array(userCount).fill(0)
    for (const u of indices) {
      counts[u]++
    }
    for (const c of counts) {
      assert.equal(c, 10)
    }
    assert.equal(indices[0], 0)
    assert.equal(indices[9], 0)
    assert.equal(indices[10], 1)
    assert.equal(indices[999], 99)
  })
})
