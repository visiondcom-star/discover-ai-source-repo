"use client";

import { useState, useEffect } from "react";

export function useAuth() {
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem("token");
    if (token) {
      fetch("/api/v1/auth/me", {
        headers: {
          "Authorization": `Bearer ${token}`,
          "X-Tenant-Slug": "algeria",
        },
      })
        .then((r) => r.ok ? r.json() : Promise.reject())
        .then((data) => setUser(data))
        .catch(() => localStorage.removeItem("token"))
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (email: string, password: string): Promise<boolean> => {
    try {
      const res = await fetch("/api/v1/auth/login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Tenant-Slug": "algeria",
        },
        body: JSON.stringify({ email, password }),
      });
      if (!res.ok) return false;
      const data = await res.json();
      localStorage.setItem("token", data.access_token);
      setUser(data);
      return true;
    } catch {
      return false;
    }
  };

  const logout = () => {
    localStorage.removeItem("token");
    setUser(null);
    window.location.reload();
  };

  return { user, loading, login, logout, isAuthenticated: !!user };
}
