"use client";

import type { Tenant } from "@/types";

export function Footer({ tenant }: { tenant: Tenant | null }) {
  return (
    <footer className="bg-brand-dark text-white py-12 border-t border-brand">
      <div className="max-w-6xl mx-auto px-4">
        <div className="grid md:grid-cols-4 gap-8">
          <div>
            <h3 className="font-display font-semibold text-lg mb-4 text-white">{tenant?.name || "Discover AI"}</h3>
            <p className="text-brand-tint/70 text-sm leading-relaxed">
              Votre compagnon de voyage intelligent. Explorez, planifiez, et découvrez le monde autrement.
            </p>
          </div>
          <div>
            <h4 className="font-semibold mb-4 text-white">Navigation</h4>
            <ul className="space-y-2 text-brand-tint/70 text-sm">
              <li><a href="/pois" className="hover:text-white transition">Points d&apos;intérêt</a></li>
              <li><a href="/trips" className="hover:text-white transition">Planifier un voyage</a></li>
              <li><a href="/chat" className="hover:text-white transition">Guide IA</a></li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold mb-4 text-white">Ressources</h4>
            <ul className="space-y-2 text-brand-tint/70 text-sm">
              <li><a href="#" className="hover:text-white transition">API Documentation</a></li>
              <li><a href="#" className="hover:text-white transition">Contribuer</a></li>
              <li><a href="#" className="hover:text-white transition">Blog</a></li>
            </ul>
          </div>
          <div>
            <h4 className="font-semibold mb-4 text-white">Contact</h4>
            <p className="text-brand-tint/70 text-sm">contact@discoverai.travel</p>
            <p className="text-brand-tint/60 text-xs mt-2">Version 1.0.0</p>
          </div>
        </div>
        <div className="border-t border-white/10 mt-8 pt-8 text-center text-brand-tint/60 text-xs">
          © 2026 {tenant?.name || "Discover AI"}. Tous droits réservés.
        </div>
      </div>
    </footer>
  );
}
