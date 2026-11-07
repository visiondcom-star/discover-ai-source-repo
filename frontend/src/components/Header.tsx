"use client";

import Link from "next/link";
import { Menu, X, Globe } from "lucide-react";
import { useState } from "react";
import type { Tenant } from "@/types";

export function Header({ tenant }: { tenant: Tenant | null }) {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <header className="bg-white/95 backdrop-blur-md border-b border-gray-200/80 sticky top-0 z-50">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5 font-display font-semibold text-xl text-ink">
          <div className="w-8 h-8 rounded-full bg-brand text-white flex items-center justify-center font-bold text-sm shadow-xs">
            <span>D</span>
          </div>
          <span>{tenant?.name || "Discover AI"}</span>
        </Link>

        <nav className="hidden md:flex items-center gap-2">
          <Link
            href="/pois"
            className="px-4 py-2 rounded-full text-sm font-semibold text-ink-soft hover:text-brand hover:bg-brand-tint/50 transition"
          >
            Sites
          </Link>
          <Link
            href="/trips"
            className="px-4 py-2 rounded-full text-sm font-semibold text-ink-soft hover:text-brand hover:bg-brand-tint/50 transition"
          >
            Voyages
          </Link>
          <Link
            href="/chat"
            className="px-4 py-2 rounded-full text-sm font-semibold text-ink-soft hover:text-brand hover:bg-brand-tint/50 transition"
          >
            Guide IA
          </Link>
          <button className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-semibold text-ink-soft hover:text-brand border border-gray-200 ml-2">
            <Globe size={15} strokeWidth={1.75} />
            <span>FR</span>
          </button>
        </nav>

        <button 
          className="md:hidden p-2 rounded-full hover:bg-gray-100 transition"
          onClick={() => setMobileOpen(!mobileOpen)}
          aria-label="Menu"
        >
          {mobileOpen ? <X size={20} strokeWidth={1.75} /> : <Menu size={20} strokeWidth={1.75} />}
        </button>
      </div>

      {mobileOpen && (
        <div className="md:hidden border-t border-gray-200/80 bg-white px-4 py-4 space-y-2">
          <Link href="/pois" className="block px-4 py-2 rounded-full text-sm font-semibold text-ink-soft hover:bg-brand-tint/50">Sites</Link>
          <Link href="/trips" className="block px-4 py-2 rounded-full text-sm font-semibold text-ink-soft hover:bg-brand-tint/50">Voyages</Link>
          <Link href="/chat" className="block px-4 py-2 rounded-full text-sm font-semibold text-ink-soft hover:bg-brand-tint/50">Guide IA</Link>
        </div>
      )}
    </header>
  );
}
