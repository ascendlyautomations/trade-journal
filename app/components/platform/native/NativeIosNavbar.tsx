"use client"

import dynamic from "next/dynamic"

/**
 * Native iOS top navbar — currently the same Navbar as web (pixel-identical).
 * Future compact iOS navigation replaces this implementation only.
 */
const Navbar = dynamic(() => import("@/app/components/Navbar"), {
  ssr: false,
  loading: () => null,
})

export default function NativeIosNavbar() {
  return <Navbar />
}
