"use client";

import { useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { api } from "@/lib/api";
import { TENANT_SLUG } from "@/lib/tenant";
import { POICard } from "@/components/POICard";
import {
  Map,
  Search,
  MessageCircle,
  Calendar,
  User,
  Home,
  Landmark,
  Trees,
  Compass,
  Utensils,
  Sparkles,
  Castle,
  Palmtree,
  Sun,
  Mountain,
  Waves,
  ShoppingBag,
  PlusCircle,
  ArrowRight,
  Send,
  Star,
  MapPin,
  Clock,
  CheckCircle2,
  ChevronRight,
  X,
  CreditCard,
  Settings,
  Bell,
  Globe,
} from "lucide-react";
import type { ChatMessage, POI, User as AppUser } from "@/types";

export function AppShell({ onLogout }: { onLogout?: () => void }) {
  const [activeTab, setActiveTab] = useState("home");
  const [exploreFilter, setExploreFilter] = useState("");
  const { user, logout } = useAuth();

  const tabs = [
    { id: "home", label: "Accueil", icon: Home },
    { id: "explore", label: "Explorer", icon: Search },
    { id: "bookings", label: "Réservations", icon: Calendar },
    { id: "assistant", label: "Assistant", icon: MessageCircle },
    { id: "profile", label: "Profil", icon: User },
  ];

  const handleSelectTravelType = (typeId: string) => {
    setExploreFilter(typeId);
    setActiveTab("explore");
  };

  return (
    <div className="min-h-screen flex flex-col bg-canvas text-ink">
      {/* Top Header */}
      <header className="sticky top-0 z-30 bg-white/90 backdrop-blur-md border-b border-gray-200/80 px-4 sm:px-6 py-3 flex items-center justify-between shadow-xs">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-xl bg-brand text-white flex items-center justify-center font-bold text-sm shadow-sm">
            <span>D</span>
          </div>
          <div>
            <h1 className="font-bold text-base tracking-tight text-brand">
              Discover AI
            </h1>
            <p className="text-[10px] text-ink-soft hidden sm:block">
              Destination OS • Algérie
            </p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs text-ink-soft bg-canvas px-3 py-1.5 rounded-full border border-gray-200/60 font-medium">
            {user?.email}
          </span>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 overflow-y-auto pb-20 max-w-5xl w-full mx-auto p-4 sm:p-6">
        {activeTab === "home" && (
          <HomeTab
            user={user}
            onSelectType={handleSelectTravelType}
            onGoToExplore={() => setActiveTab("explore")}
            onGoToChat={() => setActiveTab("assistant")}
          />
        )}
        {activeTab === "explore" && (
          <ExploreTab initialCategory={exploreFilter} />
        )}
        {activeTab === "bookings" && <BookingsTab />}
        {activeTab === "assistant" && <AssistantTab user={user} />}
        {activeTab === "profile" && (
          <ProfileTab user={user} onLogout={onLogout ?? logout} />
        )}
      </main>

      {/* Bottom Floating Navigation Bar */}
      <nav className="fixed bottom-0 left-0 right-0 z-40 bg-white/95 backdrop-blur-md border-t border-gray-200/80 px-2 py-2 shadow-float max-w-lg mx-auto sm:rounded-t-2xl">
        <div className="flex justify-around items-center">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => {
                  if (tab.id === "explore") setExploreFilter("");
                  setActiveTab(tab.id);
                }}
                className={`flex flex-col items-center gap-1 px-3 py-1.5 rounded-xl transition-all duration-200 ${
                  isActive
                    ? "text-brand bg-brand-tint/60 font-semibold"
                    : "text-ink-soft hover:text-ink"
                }`}
                aria-pressed={isActive}
              >
                <Icon
                  size={20}
                  className={isActive ? "text-brand stroke-[2.4]" : "stroke-[1.8]"}
                />
                <span className="text-[11px]">{tab.label}</span>
              </button>
            );
          })}
        </div>
      </nav>
    </div>
  );
}

// ----------------------------------------------------------------------------
// 1. Écran d'Accueil (Screen 1 du Blueprint)
// ----------------------------------------------------------------------------
const TRAVEL_TYPES = [
  { id: "culture", label: "Culture & Médinas", icon: Landmark, bg: "bg-amber-50 text-amber-900 border-amber-200/70" },
  { id: "historical", label: "Histoire & Antiquité", icon: Castle, bg: "bg-yellow-50 text-yellow-900 border-yellow-200/70" },
  { id: "nature", label: "Nature & Parcs", icon: Trees, bg: "bg-emerald-50 text-emerald-900 border-emerald-200/70" },
  { id: "desert", label: "Sahara & Oasis", icon: Sun, bg: "bg-orange-50 text-orange-900 border-orange-200/70" },
  { id: "adventure", label: "Aventure & Trekking", icon: Mountain, bg: "bg-stone-50 text-stone-900 border-stone-200/70" },
  { id: "food", label: "Gastronomie & Terroir", icon: Utensils, bg: "bg-rose-50 text-rose-900 border-rose-200/70" },
  { id: "beaches", label: "Plages & Littoral", icon: Palmtree, bg: "bg-sky-50 text-sky-900 border-sky-200/70" },
  { id: "monuments", label: "Monuments & Sites", icon: Compass, bg: "bg-indigo-50 text-indigo-900 border-indigo-200/70" },
  { id: "crafts", label: "Artisanat & Souks", icon: ShoppingBag, bg: "bg-purple-50 text-purple-900 border-purple-200/70" },
  { id: "thermal", label: "Thermalisme & Eaux", icon: Waves, bg: "bg-teal-50 text-teal-900 border-teal-200/70" },
  { id: "wellness", label: "Détente & Hammams", icon: Sparkles, bg: "bg-pink-50 text-pink-900 border-pink-200/70" },
  { id: "more", label: "Toutes les activités", icon: PlusCircle, bg: "bg-gray-50 text-gray-900 border-gray-200/70" },
];

function HomeTab({
  user,
  onSelectType,
  onGoToExplore,
  onGoToChat,
}: {
  user: AppUser | null;
  onSelectType: (id: string) => void;
  onGoToExplore: () => void;
  onGoToChat: () => void;
}) {
  const firstName = user?.full_name?.split(" ")[0] || "Samir";

  return (
    <div className="space-y-6">
      {/* Greeting Banner */}
      <div className="bg-white rounded-2xl p-6 shadow-xs border border-gray-100 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl sm:text-3xl font-bold text-ink">
            Bonjour, {firstName} 👋
          </h2>
          <p className="text-xs sm:text-sm text-ink-soft mt-1">
            Quel type de voyage souhaitez-vous vivre aujourd&apos;hui ?
          </p>
        </div>
        <button
          onClick={onGoToChat}
          className="inline-flex items-center gap-2 px-4 py-2 bg-brand-tint text-brand rounded-xl font-semibold text-xs hover:bg-brand-tint/80 transition"
        >
          <Sparkles size={15} />
          <span>Demander à l&apos;IA</span>
        </button>
      </div>

      {/* Grid of 12 Travel Types (Blueprint Screen 1) */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-base font-bold text-ink">
            Sélectionnez votre type de séjour
          </h3>
          <span className="text-xs text-ink-soft">12 catégories</span>
        </div>

        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-3">
          {TRAVEL_TYPES.map((type) => {
            const Icon = type.icon;
            return (
              <button
                key={type.id}
                onClick={() => onSelectType(type.id)}
                className={`flex flex-col items-center justify-center p-3 sm:p-4 rounded-2xl border ${type.bg} hover:shadow-card hover:-translate-y-0.5 transition-all duration-200 text-center group`}
              >
                <div className="w-10 h-10 rounded-xl bg-white/90 flex items-center justify-center mb-2 shadow-xs group-hover:scale-110 transition-transform">
                  <Icon size={20} />
                </div>
                <span className="text-xs font-semibold">{type.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Hero Inspiration Banner (Blueprint Screen 1 Bottom) */}
      <div className="relative rounded-2xl overflow-hidden shadow-card border border-gray-100 bg-gradient-to-r from-brand to-brand-dark text-white p-6 sm:p-8">
        <div className="relative z-10 max-w-lg">
          <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-white/20 text-white backdrop-blur-md mb-3 inline-block">
            Inspiration Saisonnière
          </span>
          <h3 className="text-xl sm:text-2xl font-bold mb-2">
            L&apos;Algérie vous attend
          </h3>
          <p className="text-xs sm:text-sm text-brand-tint/90 mb-5 leading-relaxed">
            Des paysages grandioses, une histoire millénaire et une hospitalité unique.
            Laissez notre guide intelligent façonner votre itinéraire idéal.
          </p>
          <button
            onClick={onGoToExplore}
            className="px-5 py-2.5 bg-white text-brand rounded-xl font-bold text-xs sm:text-sm hover:bg-brand-tint transition shadow-sm inline-flex items-center gap-2"
          >
            <span>Commencer l&apos;exploration</span>
            <ArrowRight size={16} />
          </button>
        </div>
      </div>

      {/* Quick Action Cards */}
      <div className="grid grid-cols-2 gap-4">
        <div
          onClick={onGoToExplore}
          className="bg-white rounded-2xl p-5 shadow-xs border border-gray-100 hover:shadow-card hover:-translate-y-0.5 transition cursor-pointer flex items-center gap-4"
        >
          <div className="w-12 h-12 rounded-xl bg-brand-tint text-brand flex items-center justify-center">
            <Map size={24} />
          </div>
          <div>
            <p className="font-bold text-sm text-ink">Explorer la carte</p>
            <p className="text-xs text-ink-soft">Lieux, monuments et hôtels</p>
          </div>
        </div>

        <div
          onClick={onGoToChat}
          className="bg-white rounded-2xl p-5 shadow-xs border border-gray-100 hover:shadow-card hover:-translate-y-0.5 transition cursor-pointer flex items-center gap-4"
        >
          <div className="w-12 h-12 rounded-xl bg-accent/20 text-accent-dark flex items-center justify-center">
            <MessageCircle size={24} />
          </div>
          <div>
            <p className="font-bold text-sm text-ink">Assistant IA</p>
            <p className="text-xs text-ink-soft">Conseils & conciergerie</p>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// 2. Écran Explorer (Screen 4 du Blueprint)
// ----------------------------------------------------------------------------
const EXPLORE_CATEGORIES = [
  { id: "", label: "Toutes" },
  { id: "culture", label: "Culture" },
  { id: "historical", label: "Histoire" },
  { id: "nature", label: "Nature" },
  { id: "desert", label: "Sahara & Oasis" },
  { id: "adventure", label: "Aventure" },
  { id: "food", label: "Gastronomie" },
  { id: "beaches", label: "Plages & Mer" },
];

function ExploreTab({ initialCategory = "" }: { initialCategory?: string }) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState(initialCategory);
  const [pois, setPois] = useState<POI[]>([]);
  const [selectedPoi, setSelectedPoi] = useState<POI | null>(null);
  const [loading, setLoading] = useState(false);

  const search = async (forcedQuery?: string, forcedCategory?: string) => {
    setLoading(true);
    const q = forcedQuery !== undefined ? forcedQuery : query;
    const cat = forcedCategory !== undefined ? forcedCategory : category;

    try {
      let url = `/api/v1/pois/?page_size=20`;
      if (q) url += `&search=${encodeURIComponent(q)}`;
      if (cat) url += `&category=${encodeURIComponent(cat)}`;

      const res = await fetch(url, {
        headers: { "X-Tenant-Slug": TENANT_SLUG },
      });
      const data: { items?: POI[] } = await res.json();
      setPois(data.items ?? []);
    } catch {
      setPois([]);
    }
    setLoading(false);
  };

  // Trigger search on mount or when category changes
  useState(() => {
    search(query, initialCategory);
  });

  return (
    <div className="space-y-5">
      {/* Search Input */}
      <div className="relative">
        <input
          type="text"
          placeholder="Rechercher un lieu..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && search()}
          className="w-full pl-12 pr-12 py-3.5 bg-white border border-gray-200/90 rounded-2xl text-sm text-ink shadow-xs focus:ring-2 focus:ring-brand/30 focus:border-brand transition outline-hidden"
        />
        <Search
          size={18}
          className="absolute left-4 top-1/2 -translate-y-1/2 text-ink-soft"
        />
        <button
          onClick={() => search()}
          className="absolute right-2 top-1/2 -translate-y-1/2 px-3 py-1.5 bg-brand text-white rounded-xl text-xs font-semibold hover:bg-brand-dark transition"
        >
          Chercher
        </button>
      </div>

      {/* Filter Chips */}
      <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none">
        {EXPLORE_CATEGORIES.map((cat) => {
          const isSelected = category === cat.id;
          return (
            <button
              key={cat.id}
              onClick={() => {
                setCategory(cat.id);
                search(query, cat.id);
              }}
              className={`px-3.5 py-1.5 rounded-full text-xs font-semibold whitespace-nowrap transition-all duration-200 ${
                isSelected
                  ? "bg-brand text-white shadow-xs"
                  : "bg-white text-ink-soft border border-gray-200/80 hover:bg-gray-50"
              }`}
            >
              {cat.label}
            </button>
          );
        })}
      </div>

      {/* Loading Skeleton with .animate-pulse required by smoke test */}
      {loading && (
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-5">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="bg-white rounded-2xl border border-gray-100 overflow-hidden shadow-xs animate-pulse h-72"
            >
              <div className="h-44 bg-gray-200" />
              <div className="p-4 space-y-2">
                <div className="h-4 bg-gray-200 rounded w-3/4" />
                <div className="h-3 bg-gray-100 rounded w-1/2" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Empty States */}
      {!loading && pois.length === 0 && query && (
        <div className="bg-white rounded-2xl p-8 text-center border border-gray-100 shadow-xs">
          <p className="text-gray-500 text-sm">Aucun lieu trouvé</p>
        </div>
      )}

      {!loading && pois.length === 0 && !query && (
        <div className="bg-white rounded-2xl p-8 text-center border border-gray-100 shadow-xs">
          <p className="text-gray-400 text-sm">Tapez un mot-clé pour rechercher</p>
        </div>
      )}

      {/* POI Cards Grid */}
      {!loading && pois.length > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {pois.map((poi) => (
            <POICard
              key={poi.id}
              poi={poi}
              onSelect={(p) => setSelectedPoi(p)}
            />
          ))}
        </div>
      )}

      {/* POI Detail Modal (Blueprint Screen 4) */}
      {selectedPoi && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-3xl max-w-lg w-full max-h-[90vh] overflow-y-auto shadow-float border border-gray-100 relative">
            <button
              onClick={() => setSelectedPoi(null)}
              className="absolute top-4 right-4 z-10 w-9 h-9 bg-white/80 hover:bg-white backdrop-blur-md rounded-full flex items-center justify-center text-ink shadow-sm transition"
            >
              <X size={18} />
            </button>

            <div className="relative h-56 w-full overflow-hidden bg-gray-100">
              <img
                src={
                  selectedPoi.images?.[0] ||
                  "https://images.unsplash.com/photo-1596401057633-54a8fe8ef647?q=80&w=800&auto=format&fit=crop"
                }
                alt={selectedPoi.name}
                className="w-full h-full object-cover"
              />
              <div className="absolute top-4 left-4 bg-white/90 backdrop-blur-md text-brand text-xs font-bold px-3 py-1 rounded-full">
                {selectedPoi.category}
              </div>
            </div>

            <div className="p-6">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-1.5">
                  <Star size={16} className="fill-accent text-accent" />
                  <span className="font-bold text-sm">
                    {selectedPoi.average_rating ? selectedPoi.average_rating.toFixed(1) : "4.9"}
                  </span>
                  <span className="text-xs text-ink-soft">
                    ({selectedPoi.review_count || 120} avis)
                  </span>
                </div>
                <div className="flex items-center gap-1 text-xs text-ink-soft">
                  <Clock size={14} />
                  <span>{selectedPoi.duration_minutes} min</span>
                </div>
              </div>

              <h3 className="text-2xl font-bold text-ink mb-1">
                {selectedPoi.name}
              </h3>
              <p className="text-xs text-brand-bright font-medium flex items-center gap-1 mb-4">
                <MapPin size={13} />
                <span>{selectedPoi.city}, Algérie</span>
              </p>

              <p className="text-sm text-ink-soft leading-relaxed mb-6">
                {selectedPoi.description}
              </p>

              <div className="space-y-2.5 py-4 border-t border-b border-gray-100 text-xs text-ink-soft mb-6">
                <div className="flex justify-between">
                  <span>Horaires habituels :</span>
                  <span className="font-semibold text-ink">08:00 - 18:00</span>
                </div>
                <div className="flex justify-between">
                  <span>Tarif indicatif :</span>
                  <span className="font-semibold text-brand">300 DA (Visite libre)</span>
                </div>
                <div className="flex justify-between">
                  <span>Visites guidées :</span>
                  <span className="font-semibold text-ink">Disponible sur place</span>
                </div>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={() => setSelectedPoi(null)}
                  className="flex-1 py-3 border border-gray-200 text-ink rounded-xl font-semibold text-xs hover:bg-gray-50 transition"
                >
                  Fermer
                </button>
                <button
                  onClick={() => {
                    alert("Réservation initiée pour " + selectedPoi.name);
                    setSelectedPoi(null);
                  }}
                  className="flex-1 py-3 bg-brand text-white rounded-xl font-semibold text-xs hover:bg-brand-dark transition shadow-md"
                >
                  Réserver la visite
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ----------------------------------------------------------------------------
// 3. Écran Réservations (Screen 9 du Blueprint)
// ----------------------------------------------------------------------------
const DEMO_BOOKINGS = [
  {
    id: "1",
    title: "Hôtel El Aurassi",
    city: "Alger",
    dates: "12 - 16 Juin 2026",
    category: "Hébergement",
    status: "Confirmée",
    image:
      "https://images.unsplash.com/photo-1566073771259-6a8506099945?q=80&w=800&auto=format&fit=crop",
  },
  {
    id: "2",
    title: "Restaurant Le Corsaire",
    city: "Alger",
    dates: "13 Juin 2026 à 20:00",
    category: "Table gastronomique",
    status: "Confirmée",
    image:
      "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?q=80&w=800&auto=format&fit=crop",
  },
  {
    id: "3",
    title: "Visite guidée Casbah d'Alger",
    city: "Alger",
    dates: "14 Juin 2026 à 10:00",
    category: "Expérience culturelle",
    status: "Confirmée",
    image:
      "https://images.unsplash.com/photo-1596401057633-54a8fe8ef647?q=80&w=800&auto=format&fit=crop",
  },
];

function BookingsTab() {
  const [subTab, setSubTab] = useState<"upcoming" | "past">("upcoming");

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl sm:text-2xl font-bold text-ink">Réservations</h2>
          <p className="text-xs text-ink-soft">
            Gérez vos séjours, activités et expériences confirmées
          </p>
        </div>
        <div className="flex bg-white rounded-xl p-1 border border-gray-200/80 shadow-xs">
          <button
            onClick={() => setSubTab("upcoming")}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
              subTab === "upcoming"
                ? "bg-brand text-white shadow-xs"
                : "text-ink-soft hover:text-ink"
            }`}
          >
            À venir (3)
          </button>
          <button
            onClick={() => setSubTab("past")}
            className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition ${
              subTab === "past"
                ? "bg-brand text-white shadow-xs"
                : "text-ink-soft hover:text-ink"
            }`}
          >
            Passées
          </button>
        </div>
      </div>

      {subTab === "upcoming" ? (
        <div className="space-y-4">
          {DEMO_BOOKINGS.map((booking) => (
            <div
              key={booking.id}
              className="bg-white rounded-2xl border border-gray-100 overflow-hidden shadow-xs hover:shadow-card transition flex flex-col sm:flex-row"
            >
              <div className="sm:w-48 h-36 relative overflow-hidden bg-gray-100">
                <img
                  src={booking.image}
                  alt={booking.title}
                  className="w-full h-full object-cover"
                />
                <span className="sm:hidden absolute top-3 left-3 bg-emerald-100 text-emerald-800 text-[10px] font-bold px-2 py-0.5 rounded-full">
                  {booking.status}
                </span>
              </div>
              <div className="p-4 sm:p-5 flex-1 flex flex-col justify-between">
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs font-semibold text-brand-bright">
                      {booking.category}
                    </span>
                    <span className="hidden sm:inline-flex items-center gap-1 bg-emerald-50 text-emerald-700 text-xs font-semibold px-2.5 py-0.5 rounded-full border border-emerald-200">
                      <CheckCircle2 size={12} />
                      <span>{booking.status}</span>
                    </span>
                  </div>
                  <h3 className="font-bold text-base text-ink mb-1">
                    {booking.title}
                  </h3>
                  <div className="flex items-center gap-4 text-xs text-ink-soft">
                    <span className="flex items-center gap-1">
                      <MapPin size={13} />
                      {booking.city}
                    </span>
                    <span className="flex items-center gap-1">
                      <Calendar size={13} />
                      {booking.dates}
                    </span>
                  </div>
                </div>
                <div className="pt-3 mt-3 border-t border-gray-100 flex items-center justify-between">
                  <span className="text-xs text-brand font-medium hover:underline cursor-pointer">
                    Voir les détails du voucher
                  </span>
                  <button className="text-xs font-semibold text-ink-soft hover:text-red-600 transition">
                    Modifier
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-white rounded-2xl p-12 text-center border border-gray-100 shadow-xs">
          <Calendar size={36} className="mx-auto text-ink-soft mb-2 opacity-50" />
          <p className="text-sm font-semibold text-ink">Aucun voyage archivé</p>
          <p className="text-xs text-ink-soft mt-1">Vos séjours passés apparaîtront ici.</p>
        </div>
      )}
    </div>
  );
}

// ----------------------------------------------------------------------------
// 4. Écran Assistant IA (Screen 6 du Blueprint)
// ----------------------------------------------------------------------------
const QUICK_PROMPTS = [
  { id: "restaurant", icon: "🍽️", text: "Trouver un restaurant près de moi" },
  { id: "today", icon: "🏛️", text: "Que faire aujourd'hui ?" },
  { id: "hotel", icon: "🏨", text: "Me recommander un hôtel" },
  { id: "translate", icon: "🌐", text: "Traduire cette page" },
];

function AssistantTab({ user }: { user: AppUser | null }) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);

  const firstName = user?.full_name?.split(" ")[0] || "Samir";

  const send = async (overrideText?: string) => {
    const textToSend = overrideText || input;
    if (!textToSend.trim()) return;

    const userMsg: ChatMessage = { role: "user", content: textToSend };
    setMessages((prev) => [...prev, userMsg]);
    if (!overrideText) setInput("");
    setLoading(true);

    try {
      const res = await api.post<{ message: string }>("/chat/", {
        message: textToSend,
      });
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: res.data.message },
      ]);
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Désolé, une erreur est survenue.";
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: message },
      ]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-140px)] bg-white rounded-3xl border border-gray-200/80 shadow-card overflow-hidden">
      {/* Assistant Header (Blueprint Screen 6) */}
      <div className="p-4 sm:p-5 border-b border-gray-100 bg-canvas/60 flex items-center gap-3">
        <div className="w-10 h-10 rounded-2xl bg-brand text-white flex items-center justify-center font-bold text-lg shadow-sm">
          <span>AI</span>
        </div>
        <div>
          <h2 className="font-bold text-sm sm:text-base text-ink flex items-center gap-2">
            <span>Assistant IA</span>
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
          </h2>
          <p className="text-xs text-ink-soft">
            Bienvenue ! Je suis votre guide personnel.
          </p>
        </div>
      </div>

      {/* Messages Scroll Area */}
      <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
        {/* Welcome message with 4 quick recommendation cards (Blueprint Screen 6) */}
        {messages.length === 0 && (
          <div className="space-y-6">
            <div className="bg-brand-tint/60 rounded-2xl p-5 border border-brand/10">
              <p className="text-sm font-bold text-brand mb-1">
                Bonjour {firstName},
              </p>
              <p className="text-xs text-ink-soft leading-relaxed">
                Je suis votre assistant IA personnel. Comment puis-je vous aider à
                planifier ou embellir votre séjour aujourd&apos;hui ?
              </p>
            </div>

            <div>
              <p className="text-xs font-semibold text-ink-soft mb-3">
                Suggestions rapides :
              </p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                {QUICK_PROMPTS.map((prompt) => (
                  <button
                    key={prompt.id}
                    onClick={() => send(prompt.text)}
                    className="flex items-center gap-2.5 p-3 rounded-xl bg-canvas border border-gray-200/80 hover:border-brand/40 hover:bg-white text-left transition group shadow-2xs"
                  >
                    <span className="text-base">{prompt.icon}</span>
                    <span className="text-xs font-semibold text-ink group-hover:text-brand transition-colors">
                      {prompt.text}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Conversation history preserving .chat-message for tests */}
        {messages.map((msg, i) => (
          <div
            key={i}
            className={`chat-message p-4 rounded-2xl max-w-[85%] text-xs sm:text-sm leading-relaxed ${
              msg.role === "user"
                ? "bg-brand text-white ml-auto rounded-tr-xs shadow-sm"
                : "bg-canvas text-ink mr-auto rounded-tl-xs border border-gray-200/60 shadow-2xs"
            }`}
          >
            {msg.content}
          </div>
        ))}

        {loading && (
          <div className="chat-message bg-canvas p-4 rounded-2xl rounded-tl-xs w-20 border border-gray-200/60">
            <div className="flex gap-1.5">
              <div className="w-2 h-2 bg-brand/50 rounded-full animate-bounce" />
              <div
                className="w-2 h-2 bg-brand/50 rounded-full animate-bounce"
                style={{ animationDelay: "0.15s" }}
              />
              <div
                className="w-2 h-2 bg-brand/50 rounded-full animate-bounce"
                style={{ animationDelay: "0.3s" }}
              />
            </div>
          </div>
        )}
      </div>

      {/* Input Area */}
      <div className="p-3 sm:p-4 border-t border-gray-100 bg-white flex gap-2 items-center">
        <input
          type="text"
          placeholder="Posez-moi une question..."
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && send()}
          disabled={loading}
          className="flex-1 px-4 py-3 bg-canvas border border-gray-200 rounded-xl text-xs sm:text-sm focus:bg-white focus:ring-2 focus:ring-brand/30 focus:border-brand transition outline-hidden"
        />
        <button
          onClick={() => send()}
          disabled={loading || !input.trim()}
          className="p-3 bg-brand text-white rounded-xl hover:bg-brand-dark transition disabled:opacity-40 shadow-sm"
        >
          <Send size={18} />
        </button>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// 5. Écran Profil (Screen 6 du Blueprint additionnel)
// ----------------------------------------------------------------------------
function ProfileTab({
  user,
  onLogout,
}: {
  user: AppUser | null;
  onLogout: () => void;
}) {
  const settingsLinks = [
    { icon: User, label: "Informations personnelles" },
    { icon: Compass, label: "Préférences de voyage" },
    { icon: CreditCard, label: "Modes de paiement" },
    { icon: Globe, label: "Langues & Devises (Français • DZD/EUR)" },
    { icon: Bell, label: "Notifications" },
    { icon: Settings, label: "Paramètres de confidentialité" },
  ];

  return (
    <div className="space-y-6">
      {/* Profile Card */}
      <div className="bg-white rounded-2xl p-6 shadow-xs border border-gray-100 flex items-center gap-4">
        <div className="w-16 h-16 rounded-full bg-brand-tint text-brand flex items-center justify-center font-bold text-2xl border-2 border-brand/20">
          <span>{user?.email?.charAt(0).toUpperCase() || "S"}</span>
        </div>
        <div>
          <h2 className="text-lg font-bold text-ink">
            {user?.full_name || "Samir Belkacem"}
          </h2>
          <p className="text-xs text-ink-soft">{user?.email || "demo@algeria.travel"}</p>
          <span className="inline-block mt-2 text-[10px] font-semibold px-2 py-0.5 bg-emerald-100 text-emerald-800 rounded-full">
            Membre Explorateur
          </span>
        </div>
      </div>

      {/* Navigation settings links */}
      <div className="bg-white rounded-2xl border border-gray-100 shadow-xs divide-y divide-gray-100 overflow-hidden">
        {settingsLinks.map((item, idx) => {
          const Icon = item.icon;
          return (
            <div
              key={idx}
              className="p-4 flex items-center justify-between hover:bg-canvas/60 transition cursor-pointer"
            >
              <div className="flex items-center gap-3">
                <Icon size={18} className="text-brand" />
                <span className="text-xs sm:text-sm font-medium text-ink">
                  {item.label}
                </span>
              </div>
              <ChevronRight size={16} className="text-ink-soft" />
            </div>
          );
        })}
      </div>

      {/* Logout button (smoke test contract) */}
      <div className="pt-2">
        <button
          onClick={onLogout}
          className="w-full py-3.5 bg-rose-50 text-rose-700 border border-rose-200/80 rounded-2xl font-semibold text-xs sm:text-sm hover:bg-rose-100 transition shadow-2xs"
        >
          Se déconnecter
        </button>
      </div>
    </div>
  );
}

