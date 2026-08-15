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
      const userData = await api.get<User>("/api/v1/auth/me");
      setUser(userData);
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
      const loginResponse = await api.post<{ access_token: string }>("/api/v1/auth/login", {
        email,
        password,
      });

      localStorage.setItem("token", loginResponse.access_token);

      // After setting the token, fetch the user data to ensure consistency.
      // The api module should now use the new token for its requests.
      const userData = await api.get<User>("/api/v1/auth/me");
      setUser(userData);
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
    // Redirect to login page instead of forcing a reload for a smoother UX.
    router.push("/login");
  }, [router]);

  return {
    user,
    loading,
    login,
    logout,
    isAuthenticated: !!user && !loading,
  };
}
