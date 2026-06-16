const PREFIX = "[getting-started]"

/** Verbose getting-started logs (dev always on; prod requires DEBUG_GETTING_STARTED=1). */
export function gsDebug(...args: unknown[]) {
  if (typeof window === "undefined") return
  if (process.env.NODE_ENV === "production") {
    try {
      if (window.localStorage.getItem("DEBUG_GETTING_STARTED") !== "1") return
    } catch {
      return
    }
  }
  console.log(PREFIX, ...args)
}
