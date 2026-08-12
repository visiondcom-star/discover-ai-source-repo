"use client";

import { useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { api } from "@/lib/api";
import { Map, Search, MessageCircle, Calendar, User, Home } from "lucide-react";

export function AppShell() {
  const [activeTab, setActiveTab] = useState("home");
  const { user, logout } = useAuth();

  const tabs = [
    { id: "home", label: "Accueil", icon: Home },
    { id: "explore", label: "Explorer", icon: Search },
    { id: "bookings", label: "Réservations", icon: Calendar },
    { id: "assistant", label: "Assistant", icon: MessageCircle },
    { id: "profile", label: "Profil", icon: User },
  ];

  return (
    <div className="min-h-screen flex flex-col bg-gray-50">
      {/* Header */}
      <header className="bg-emerald-700 text-white px-4 py-3 flex items-center justify-between">
        <h1 className="font-bold text-lg">Discover AI</h1>
        <span className="text-sm opacity-80">{user?.email}</span>
      </header>

      {/* Content */}
      <main className="flex-1 overflow-y-auto p-4">
        {activeTab === "home" && <HomeTab user={user} />}
        {activeTab === "explore" && <ExploreTab />}
        {activeTab === "bookings" && <BookingsTab />}
        {activeTab === "assistant" && <AssistantTab />}
        {activeTab === "profile" && <ProfileTab user={user} onLogout={logout} />}
      </main>

      {/* Bottom Tabs */}
      <nav className="bg-white border-t flex justify-around py-2">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex flex-col items-center gap-1 px-3 py-1 rounded-lg transition ${
                isActive ? "text-emerald-700" : "text-gray-400"
              }`}
              aria-pressed={isActive}
            >
              <Icon size={20} />
              <span className="text-xs">{tab.label}</span>
            </button>
          );
        })}
      </nav>
    </div>
  );
}

function HomeTab({ user }: { user: any }) {
  return (
    <div className="space-y-4">
      <div className="bg-white rounded-xl p-6 shadow-sm">
        <h2 className="text-2xl font-bold text-emerald-800">
          Bonjour{user?.fullName ? `, ${user.fullName}` : ""} !
        </h2>
        <p className="text-gray-600 mt-2">Prêt à découvrir de nouveaux horizons ?</p>
      </div>
      <div className="grid grid-cols-2 gap-4">
        <div className="bg-white rounded-xl p-4 shadow-sm text-center">
          <Map className="mx-auto mb-2 text-emerald-600" size={32} />
          <p className="font-medium">Explorer</p>
        </div>
        <div className="bg-white rounded-xl p-4 shadow-sm text-center">
          <MessageCircle className="mx-auto mb-2 text-emerald-600" size={32} />
          <p className="font-medium">Assistant IA</p>
        </div>
      </div>
    </div>
  );
}

function ExploreTab() {
  const [query, setQuery] = useState("");
  const [pois, setPois] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  const search = async () => {
    setLoading(true);
    try {
      const res = await fetch(`/api/v1/pois/?search=${encodeURIComponent(query)}&page_size=20`, {
        headers: { "X-Tenant-Slug": "algeria" },
      });
      const data = await res.json();
      setPois(data.items || []);
    } catch (e) {
      setPois([]);
    }
    setLoading(false);
  };

  return (
    <div className="space-y-4">
      <div className="relative">
        <input
          type="text"
          placeholder="Rechercher un lieu..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && search()}
          className="w-full px-4 py-3 border rounded-lg focus:ring-2 focus:ring-emerald-500"
        />
        <button
          onClick={search}
          className="absolute right-2 top-1/2 -translate-y-1/2 p-2 text-emerald-700"
        >
          <Search size={20} />
        </button>
      </div>

      {loading && (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="bg-white rounded-xl p-4 shadow-sm animate-pulse h-20" />
          ))}
        </div>
      )}

      {!loading && pois.length === 0 && query && (
        <p className="text-center text-gray-500 py-8">Aucun lieu trouvé</p>
      )}

      {!loading && pois.length === 0 && !query && (
        <p className="text-center text-gray-400 py-8">Tapez un mot-clé pour rechercher</p>
      )}

      <div className="space-y-3">
        {pois.map((poi) => (
          <div key={poi.id} className="bg-white rounded-xl p-4 shadow-sm">
            <h3 className="font-bold">{poi.name}</h3>
            <p className="text-sm text-gray-600">{poi.city} • {poi.category}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

function BookingsTab() {
  return (
    <div className="bg-white rounded-xl p-6 shadow-sm">
      <h2 className="text-xl font-bold mb-4">Réservations</h2>
      <p className="text-gray-500">Aucune réservation pour le moment.</p>
    </div>
  );
}

function AssistantTab() {
  const [messages, setMessages] = useState<any[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);

  const send = async () => {
    if (!input.trim()) return;
    const userMsg = { role: "user", content: input };
    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setLoading(true);

    try {
      const token = localStorage.getItem("token");
      const res = await fetch("/api/v1/chat/", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Tenant-Slug": "algeria",
          "Authorization": `Bearer ${token}`,
        },
        body: JSON.stringify({ message: input }),
      });
      if (!res.ok) {
        const errText = await res.text();
        throw new Error(`Chat API error ${res.status}: ${errText}`);
      }
      const data = await res.json();
      setMessages((prev) => [...prev, { role: "assistant", content: data.message }]);
    } catch (err: any) {
      const errorMessage = err?.message || "Désolé, une erreur est survenue.";
      setMessages((prev) => [...prev, { role: "assistant", content: errorMessage }]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-140px)] bg-white rounded-xl shadow-sm overflow-hidden">
      <div className="p-4 border-b">
        <h2 className="font-bold">Assistant</h2>
        <p className="text-sm text-gray-500">Bienvenue ! Je suis votre guide.</p>
      </div>
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {messages.length === 0 && (
          <p className="text-center text-gray-400 text-sm mt-8">
            Posez-moi une question sur votre destination.
          </p>
        )}
        {messages.map((msg, i) => (
          <div
            key={i}
            className={`chat-message p-3 rounded-lg max-w-[80%] ${
              msg.role === "user"
                ? "bg-emerald-700 text-white ml-auto"
                : "bg-gray-100 text-gray-800"
            }`}
          >
            {msg.content}
          </div>
        ))}
        {loading && (
          <div className="bg-gray-100 p-3 rounded-lg w-16">
            <div className="flex gap-1">
              <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
              <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{animationDelay:"0.1s"}} />
              <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{animationDelay:"0.2s"}} />
            </div>
          </div>
        )}
      </div>
      <div className="p-3 border-t flex gap-2">
        <input
          type="text"
          placeholder="Posez-moi une question..."
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && send()}
          className="flex-1 px-4 py-2 border rounded-lg focus:ring-2 focus:ring-emerald-500"
          disabled={loading}
        />
        <button
          onClick={send}
          disabled={loading || !input.trim()}
          className="px-4 py-2 bg-emerald-700 text-white rounded-lg hover:bg-emerald-800 transition disabled:opacity-50"
        >
          <MessageCircle size={18} />
        </button>
      </div>
    </div>
  );
}

function ProfileTab({ user, onLogout }: { user: any; onLogout: () => void }) {
  return (
    <div className="bg-white rounded-xl p-6 shadow-sm space-y-4">
      <h2 className="text-xl font-bold">Profil</h2>
      <div className="space-y-2">
        <p className="text-gray-600">Email</p>
        <p className="font-medium">{user?.email || "Non connecté"}</p>
      </div>
      <button
        onClick={onLogout}
        className="w-full py-3 bg-red-50 text-red-700 rounded-lg font-semibold hover:bg-red-100 transition"
      >
        Se déconnecter
      </button>
    </div>
  );
}
