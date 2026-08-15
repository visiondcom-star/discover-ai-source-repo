import axios from "axios";

// The API client talks to the SAME origin and lets the Next.js server proxy
// /api/* to the backend (next.config.js -> rewrites(), destination BACKEND_URL).
// Baking a backend URL into the browser bundle (NEXT_PUBLIC_API_URL) breaks
// login from host browsers: "backend:8000" only resolves inside the Docker/K8s
// network.
export const api = axios.create({
  baseURL: "/api/v1",
  headers: {
    "Content-Type": "application/json",
  },
});

// Add auth token interceptor
api.interceptors.request.use((config) => {
  const token = typeof window !== "undefined" ? localStorage.getItem("token") : null;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Response interceptor for errors
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      const url: string = error.config?.url ?? "";
      // A failed login attempt must NOT hard-redirect: the login form itself
      // displays the error banner. There is also no "/login" route in this SPA.
      if (!url.includes("/auth/login")) {
        localStorage.removeItem("token");
        if (typeof window !== "undefined" && window.location.pathname !== "/") {
          window.location.href = "/";
        }
      }
    }
    return Promise.reject(error);
  }
);
