"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";

// The web's auth state can no longer be inferred from a token in localStorage
// (the token now lives in an HttpOnly cookie, invisible to JS). We derive it from
// a real backend call: GET /auth/me succeeds only when the HttpOnly cookie is
// valid and is served with it (withCredentials). This keeps the SPA truthful after
// a cookie expires or the session is invalidated server-side.
interface User {
  id: string;
  email: string;
  full_name: string | null;
  is_admin?: boolean;
}

export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const fetchUser = useCallback(async () => {
    try {
      // Cookie-authenticated: no Authorization header needed; axios sends cookies
      // (withCredentials) and the backend falls back to the access_token cookie.
      const userData = await api.get<User>("/auth/me");
      setUser(userData.data);
    } catch {
      setUser(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchUser();
  }, [fetchUser]);

  const login = async (email: string, password: string): Promise<boolean> => {
    try {
      // Sets the HttpOnly access_token + csrf_token cookies. The token is still
      // returned in the body for mobile, but the web no longer stores it.
      await api.post<{ access_token: string }>("/auth/login", {
        email,
        password,
      });

      const userData = await api.get<User>("/auth/me");
      setUser(userData.data);
      return true;
    } catch {
      setUser(null);
      return false;
    }
  };

  const logout = useCallback(async () => {
    try {
      // Cookie invalidation: the backend clears access_token/csrf_token with
      // Max-Age=0. No localStorage cleanup needed anymore.
      await api.post("/auth/logout");
    } finally {
      setUser(null);
      // Single-page app: "/" renders the landing page once unauthenticated.
      // There is no "/login" route (the login form lives on the landing page).
      router.push("/");
    }
  }, [router]);

  return {
    user,
    loading,
    login,
    logout,
    isAuthenticated: !!user && !loading,
  };
}
