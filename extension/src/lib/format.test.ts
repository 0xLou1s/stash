import { describe, expect, it } from "vitest"

import { timeAgo } from "./format"

const now = Date.parse("2026-10-09T12:00:00Z")
const ago = (seconds: number) => new Date(now - seconds * 1000).toISOString()

describe("timeAgo", () => {
  it("says just now for under a minute", () => {
    expect(timeAgo(ago(0), now)).toBe("just now")
    expect(timeAgo(ago(59), now)).toBe("just now")
  })

  it("uses the largest whole unit", () => {
    const format = new Intl.RelativeTimeFormat(undefined, { numeric: "auto", style: "short" })
    expect(timeAgo(ago(5 * 60), now)).toBe(format.format(-5, "minute"))
    expect(timeAgo(ago(3 * 3600), now)).toBe(format.format(-3, "hour"))
    expect(timeAgo(ago(24 * 3600), now)).toBe(format.format(-1, "day"))
    expect(timeAgo(ago(14 * 24 * 3600), now)).toBe(format.format(-2, "week"))
  })
})
