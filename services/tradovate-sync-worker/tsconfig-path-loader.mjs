import { existsSync } from "node:fs"
import { dirname, resolve as resolvePath } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const root = resolvePath(dirname(fileURLToPath(import.meta.url)), "../..")

function resolveAlias(specifier) {
  const rel = specifier.slice(2)
  const base = resolvePath(root, rel)
  const candidates = [
    base,
    `${base}.ts`,
    `${base}.tsx`,
    `${base}.mts`,
    resolvePath(base, "index.ts"),
  ]
  for (const abs of candidates) {
    if (existsSync(abs)) return pathToFileURL(abs).href
  }
  return pathToFileURL(`${base}.ts`).href
}

/** Resolves `@/` imports for Node worker (same paths as tsconfig). */
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("@/")) {
    return nextResolve(resolveAlias(specifier), context)
  }
  return nextResolve(specifier, context)
}
