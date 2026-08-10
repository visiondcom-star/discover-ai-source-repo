"use client";

import Link from "next/link";
import { MapPin, Menu, X, Globe } from "lucide-react";
import { useState } from "react";

export function Header({ tenant }: { tenant: any }) {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <header className="bg-white border-b sticky top-0 z-50">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2 font-bold text-xl">
          <MapPin className="text-primary" />
          <span>{tenant?.name || "Discover AI"}</span>
        </Link>

        <nav className="hidden md:flex items-center gap-6">
          <Link href="/pois" className="text-gray-600 hover:text-primary transition">Sites</Link>
          <Link href="/trips" className="text-gray-600 hover:text-primary transition">Voyages</Link>
          <Link href="/chat" className="text-gray-600 hover:text-primary transition">Guide IA</Link>
          <button className="flex items-center gap-1 text-gray-600 hover:text-primary">
            <Globe size={18} />
            <span>FR</span>
          </button>
        </nav>

        <button 
          className="md:hidden"
          onClick={() => setMobileOpen(!mobileOpen)}
        >
          {mobileOpen ? <X /> : <Menu />}
        </button>
      </div>

      {mobileOpen && (
        <div className="md:hidden border-t bg-white px-4 py-4 space-y-3">
          <Link href="/pois" className="block text-gray-600">Sites</Link>
          <Link href="/trips" className="block text-gray-600">Voyages</Link>
          <Link href="/chat" className="block text-gray-600">Guide IA</Link>
        </div>
      )}
    </header>
  );
}
