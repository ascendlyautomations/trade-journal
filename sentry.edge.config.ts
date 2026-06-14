import * as Sentry from "@sentry/nextjs"
import { getBaseSentryOptions } from "./lib/sentry"

Sentry.init({
  ...getBaseSentryOptions(),
})
