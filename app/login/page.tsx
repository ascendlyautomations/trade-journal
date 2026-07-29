import LoginPageClient from "@/app/login/LoginPageClient"
import { isNativeIosShellRequest } from "@/lib/nativeRequest"

/**
 * Server wrapper so native iOS SSR matches the first client render
 * (no back button, native chrome). Web stays unchanged.
 */
export default async function LoginPage() {
  const initialNativeIos = await isNativeIosShellRequest()
  return <LoginPageClient initialNativeIos={initialNativeIos} />
}
