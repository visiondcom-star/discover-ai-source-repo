"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api"; // Assuming a centralized API module

// It's a good practice to define the shape of your user object.
interface User {
  // Add properties based on your user data structure, e.g.,
  id: string;
  email: string;
  name: string;
}

export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const fetchUser = useCallback(async () => {
    const token = localStorage.getItem("token");
    if (!token) {
      setLoading(false);
      return;
    }

    try {
      // Assuming api.get handles setting the auth header
      const userData = await api.get<User>("/auth/me");
      setUser(userData.data);
    } catch (error) {
      console.error("Failed to fetch user:", error);
      localStorage.removeItem("token");
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
      const loginResponse = await api.post<{ access_token: string }>("/auth/login", {
        email,
        password,
      });

      localStorage.setItem("token", loginResponse.data.access_token);

      // After setting the token, fetch the user data to ensure consistency.
      // The api module should now use the new token for its requests.
      const userData = await api.get<User>("/auth/me");
      setUser(userData.data);
      return true;
    } catch (error) {
      console.error("Login failed:", error);
      localStorage.removeItem("token");
      setUser(null);
      return false;
    }
  };

  const logout = useCallback(() => {
    localStorage.removeItem("token");
    setUser(null);
    // Single-page app: "/" renders the landing page once unauthenticated.
    // There is no "/login" route (the login form lives on the landing page).
    router.push("/");
  }, [router]);

  return {
    user,
    loading,
    login,
    logout,
    isAuthenticated: !!user && !loading,
  };
}
