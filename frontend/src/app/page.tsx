"use client";

import { useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { LandingPage, LoginForm } from "@/components/LandingPage";
import { AppShell } from "@/components/AppShell";

export default function Home() {
  const { user, login, logout, loading } = useAuth();
  const [view, setView] = useState<"landing" | "login" | "register">("landing");
  const [loginError, setLoginError] = useState("");
  const [loginLoading, setLoginLoading] = useState(false);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-700"></div>
      </div>
    );
  }

  if (user) {
    return <AppShell />;
  }

  if (view === "login") {
    return (
      <LoginForm
        onSubmit={async (email, password) => {
          setLoginLoading(true);
          setLoginError("");
          const success = await login(email, password);
          setLoginLoading(false);
          if (!success) setLoginError("Email ou mot de passe incorrect");
        }}
        onBack={() => setView("landing")}
        error={loginError}
        loading={loginLoading}
      />
    );
  }

  return (
    <LandingPage
      onLoginClick={() => setView("login")}
      onRegisterClick={() => setView("login")}
    />
  );
}
