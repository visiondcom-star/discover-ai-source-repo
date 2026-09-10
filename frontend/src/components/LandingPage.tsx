"use client";

import { useState } from "react";
import {
  Compass,
  Calendar,
  Star,
  Sparkles,
  Leaf,
  MapPin,
  ArrowRight,
  ShieldCheck,
  Globe,
} from "lucide-react";

interface LandingPageProps {
  onLoginClick: () => void;
  onRegisterClick: () => void;
}

const FEATURE_PILLS = [
  { icon: Sparkles, label: "IA personnalisée" },
  { icon: Compass, label: "GPS & Navigation" },
  { icon: Calendar, label: "Réservations" },
  { icon: Star, label: "Expériences uniques" },
  { icon: Leaf, label: "Soutien local & durable" },
];

const CURATED_DESTINATIONS = [
  {
    name: "La Casbah d'Alger",
    city: "Alger",
    category: "UNESCO • Histoire",
    rating: "4.9",
    reviews: "1.2k avis",
    image:
      "https://images.unsplash.com/photo-1596401057633-54a8fe8ef647?q=80&w=800&auto=format&fit=crop",
  },
  {
    name: "Ruines de Tipaza",
    city: "Tipaza",
    category: "UNESCO • Antiquité",
    rating: "4.9",
    reviews: "950 avis",
    image:
      "https://images.unsplash.com/photo-1544644181-1484b3fdfc62?q=80&w=800&auto=format&fit=crop",
  },
  {
    name: "Ponts de Constantine",
    city: "Constantine",
    category: "Panorama • Culture",
    rating: "4.8",
    reviews: "820 avis",
    image:
      "https://images.unsplash.com/photo-1590523741831-ab7e8b8f9c7f?q=80&w=800&auto=format&fit=crop",
  },
  {
    name: "Tassili n'Ajjer",
    city: "Djanet",
    category: "Sahara • Aventure",
    rating: "5.0",
    reviews: "640 avis",
    image:
      "https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?q=80&w=800&auto=format&fit=crop",
  },
];

export function LandingPage({ onLoginClick, onRegisterClick }: LandingPageProps) {
  return (
    <div className="min-h-screen bg-canvas text-ink flex flex-col">
      {/* Top Brand Navigation */}
      <header className="w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-5 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-brand text-white flex items-center justify-center font-bold text-xl shadow-md">
            <span>D</span>
          </div>
          <div>
            <span className="text-xl font-bold tracking-tight text-brand">DISCOVER AI</span>
            <span className="hidden sm:inline-block ml-2 text-xs text-ink-soft border-l pl-2 border-gray-300">
              The Intelligent Travel Companion
            </span>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={onLoginClick}
            className="px-4 py-2 text-sm font-semibold text-brand hover:text-brand-dark transition"
          >
            Se connecter
          </button>
          <button
            onClick={onRegisterClick}
            className="px-4 py-2 text-sm font-semibold bg-brand text-white rounded-xl hover:bg-brand-dark shadow-sm transition"
          >
            Commencer
          </button>
        </div>
      </header>

      {/* Main Hero Section */}
      <main className="flex-1 flex flex-col">
        <section className="relative overflow-hidden pt-6 pb-16 lg:pb-24">
          {/* Subtle background glow */}
          <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full max-w-6xl h-96 bg-brand/5 blur-3xl -z-10 rounded-full" />

          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="text-center max-w-3xl mx-auto mb-10">
              {/* Pill badge */}
              <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-brand-tint text-brand text-xs font-semibold mb-6 border border-brand/10">
                <Sparkles size={14} className="text-brand-bright" />
                <span>Destination OS — Algérie & Monde</span>
              </div>

              {/* Blueprint title & subtitle */}
              <h1 className="text-4xl sm:text-5xl lg:text-6xl font-extrabold text-ink tracking-tight leading-[1.15] mb-6">
                Votre voyage,{" "}
                <span className="text-brand underline decoration-accent/60 decoration-wavy decoration-2">
                  réinventé par l&apos;IA
                </span>
              </h1>

              <p className="text-base sm:text-lg text-ink-soft leading-relaxed max-w-2xl mx-auto mb-4">
                L&apos;intelligence artificielle au service de vos envies. Découvrez,
                explorez, réservez et vivez des expériences uniques, personnalisées et
                inoubliables en Algérie et au-delà.
              </p>

              <p className="text-sm font-medium italic text-brand-bright tracking-wide mb-8">
                &ldquo;Algeria like you&apos;ve never seen it&rdquo;
              </p>

              {/* Feature pills from Blueprint Image 1 */}
              <div className="flex flex-wrap items-center justify-center gap-2 sm:gap-3 mb-10">
                {FEATURE_PILLS.map((pill) => {
                  const Icon = pill.icon;
                  return (
                    <div
                      key={pill.label}
                      className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-gray-200/80 shadow-xs text-xs font-medium text-ink"
                    >
                      <Icon size={15} className="text-brand" />
                      <span>{pill.label}</span>
                    </div>
                  );
                })}
              </div>

              {/* CTA Action Card (Preserves test: "Votre voyage commence ici", "Commencer l'aventure", "J'ai déjà un compte") */}
              <div className="bg-white/90 backdrop-blur-md rounded-2xl border border-gray-200/90 shadow-card p-6 sm:p-8 max-w-md mx-auto">
                <h2 className="text-xl sm:text-2xl font-bold text-ink mb-2">
                  Votre voyage commence ici
                </h2>
                <p className="text-xs sm:text-sm text-ink-soft mb-6">
                  Découvrez les trésors cachés avec votre guide IA personnel.
                </p>

                <div className="flex flex-col gap-3">
                  <button
                    onClick={onRegisterClick}
                    className="w-full py-3.5 px-6 bg-brand text-white rounded-xl font-semibold hover:bg-brand-dark transition shadow-md flex items-center justify-center gap-2 group"
                  >
                    <span>Commencer l&apos;aventure</span>
                    <ArrowRight
                      size={18}
                      className="group-hover:translate-x-1 transition-transform"
                    />
                  </button>
                  <button
                    onClick={onLoginClick}
                    className="w-full py-3.5 px-6 bg-brand-tint/60 text-brand rounded-xl font-semibold hover:bg-brand-tint transition border border-brand/20"
                  >
                    J&apos;ai déjà un compte
                  </button>
                </div>
              </div>
            </div>

            {/* Curated Destinations Showcase */}
            <div className="mt-12">
              <div className="flex items-center justify-between mb-6">
                <div>
                  <h3 className="text-xl sm:text-2xl font-bold text-ink">
                    Destinations à la une
                  </h3>
                  <p className="text-xs sm:text-sm text-ink-soft">
                    Explorez les joyaux recommandés par notre moteur IA
                  </p>
                </div>
                <button
                  onClick={onLoginClick}
                  className="text-xs sm:text-sm font-semibold text-brand hover:underline flex items-center gap-1"
                >
                  Tout explorer →
                </button>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
                {CURATED_DESTINATIONS.map((dest) => (
                  <div
                    key={dest.name}
                    onClick={onLoginClick}
                    className="group bg-white rounded-2xl border border-gray-100 overflow-hidden shadow-xs hover:shadow-card hover:-translate-y-1 transition-all duration-300 cursor-pointer flex flex-col"
                  >
                    <div className="relative h-44 w-full overflow-hidden bg-gray-100">
                      <img
                        src={dest.image}
                        alt={dest.name}
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                        loading="lazy"
                      />
                      <div className="absolute top-3 left-3 bg-white/90 backdrop-blur-md px-2.5 py-1 rounded-full text-[11px] font-semibold text-brand">
                        {dest.category}
                      </div>
                      <div className="absolute bottom-2 left-3 flex items-center gap-1 text-white text-xs font-medium drop-shadow-md">
                        <MapPin size={13} className="text-accent" />
                        <span>{dest.city}</span>
                      </div>
                    </div>
                    <div className="p-4 flex-1 flex flex-col justify-between">
                      <div>
                        <div className="flex items-center gap-1 mb-1">
                          <Star size={14} className="fill-accent text-accent" />
                          <span className="text-xs font-bold text-ink">{dest.rating}</span>
                          <span className="text-xs text-ink-soft">({dest.reviews})</span>
                        </div>
                        <h4 className="font-bold text-sm text-ink group-hover:text-brand transition-colors">
                          {dest.name}
                        </h4>
                      </div>
                      <span className="text-xs text-brand font-medium mt-3 flex items-center gap-1">
                        Découvrir avec l&apos;IA →
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>
      </main>

      {/* Footer info */}
      <footer className="border-t border-gray-200/80 bg-white py-6 mt-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-ink-soft">
          <div className="flex items-center gap-2">
            <span className="font-bold text-brand">Discover AI</span>
            <span>— Destination Operating System</span>
          </div>
          <div className="flex items-center gap-4">
            <span className="flex items-center gap-1">
              <ShieldCheck size={14} className="text-brand-bright" />
              Multi-Tenant & Données sécurisées
            </span>
            <span className="flex items-center gap-1">
              <Globe size={14} className="text-brand-bright" />
              Algérie & International
            </span>
          </div>
        </div>
      </footer>
    </div>
  );
}

interface LoginFormProps {
  onSubmit: (email: string, password: string) => void;
  onBack: () => void;
  error?: string;
  loading?: boolean;
}

export function LoginForm({ onSubmit, onBack, error, loading }: LoginFormProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!loading) {
      onSubmit(email, password);
    }
  };

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-canvas px-4 py-8 relative">
      {/* Decorative background circle */}
      <div className="absolute top-1/3 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-brand/5 blur-3xl -z-10 rounded-full" />

      <div className="w-full max-w-md bg-white rounded-2xl shadow-card border border-gray-100 p-8 sm:p-10">
        {/* Brand logo header */}
        <div className="text-center mb-6">
          <div className="w-12 h-12 rounded-2xl bg-brand text-white mx-auto flex items-center justify-center font-bold text-2xl shadow-md mb-3">
            <span>D</span>
          </div>
          <h2 className="text-2xl font-bold text-ink tracking-tight">Se connecter</h2>
          <p className="text-xs text-ink-soft mt-1">
            Accédez à votre espace Discover AI et vos voyages
          </p>
        </div>

        {/* Error banner preserving class .bg-red-50 for Playwright test */}
        {error && (
          <div className="mb-5 p-3.5 bg-red-50 border border-red-200 text-red-700 rounded-xl text-xs font-medium flex items-center gap-2">
            <span>{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              Adresse email
            </label>
            <input
              type="email"
              placeholder="Email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full px-4 py-3 bg-canvas/50 border border-gray-200 rounded-xl text-sm focus:bg-white focus:ring-2 focus:ring-brand/30 focus:border-brand transition outline-hidden"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              Mot de passe
            </label>
            <input
              type="password"
              placeholder="Mot de passe"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="w-full px-4 py-3 bg-canvas/50 border border-gray-200 rounded-xl text-sm focus:bg-white focus:ring-2 focus:ring-brand/30 focus:border-brand transition outline-hidden"
            />
          </div>

          <div className="pt-2">
            <button
              type="submit"
              disabled={loading}
              className="w-full py-3.5 bg-brand text-white rounded-xl font-semibold hover:bg-brand-dark transition shadow-md disabled:opacity-50 text-sm flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  <span>Connexion en cours...</span>
                </>
              ) : (
                "Se connecter"
              )}
            </button>
          </div>
        </form>

        <div className="mt-6 pt-5 border-t border-gray-100 flex items-center justify-between text-xs">
          <button
            type="button"
            onClick={onBack}
            className="text-ink-soft hover:text-ink font-medium transition"
          >
            ← Retour
          </button>
          <span className="text-ink-soft">
            Démo : <code className="text-brand font-semibold">demo@algeria.travel</code>
          </span>
        </div>
      </div>
    </div>
  );
}

