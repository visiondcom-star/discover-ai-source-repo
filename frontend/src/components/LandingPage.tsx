"use client";

import { useState } from "react";

interface LandingPageProps {
  onLoginClick: () => void;
  onRegisterClick: () => void;
}

export function LandingPage({ onLoginClick, onRegisterClick }: LandingPageProps) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-br from-emerald-700 to-emerald-900 text-white px-4">
      <h1 className="text-4xl font-bold mb-4">Votre voyage commence ici</h1>
      <p className="text-lg mb-8 text-emerald-100 max-w-md text-center">
        Découvrez les trésors cachés avec votre guide IA personnel.
      </p>
      <div className="flex flex-col gap-3 w-full max-w-xs">
        <button
          onClick={onRegisterClick}
          className="w-full py-3 bg-white text-emerald-800 rounded-lg font-semibold hover:bg-emerald-50 transition"
        >
          Commencer l&apos;aventure
        </button>
        <button
          onClick={onLoginClick}
          className="w-full py-3 bg-white/20 text-white rounded-lg font-semibold hover:bg-white/30 transition backdrop-blur-sm"
        >
          J&apos;ai déjà un compte
        </button>
      </div>
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

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm bg-white rounded-xl shadow-lg p-6">
        <h2 className="text-2xl font-bold mb-6 text-center">Se connecter</h2>
        {error && (
          <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg text-sm">
            {error}
          </div>
        )}
        <div className="space-y-4">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full px-4 py-3 border rounded-lg focus:ring-2 focus:ring-emerald-500"
          />
          <input
            type="password"
            placeholder="Mot de passe"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full px-4 py-3 border rounded-lg focus:ring-2 focus:ring-emerald-500"
          />
          <button
            onClick={() => onSubmit(email, password)}
            disabled={loading}
            className="w-full py-3 bg-emerald-700 text-white rounded-lg font-semibold hover:bg-emerald-800 transition disabled:opacity-50"
          >
            {loading ? "Connexion..." : "Se connecter"}
          </button>
        </div>
        <button onClick={onBack} className="w-full mt-4 text-sm text-gray-500 hover:text-gray-700">
          Retour
        </button>
      </div>
    </div>
  );
}
