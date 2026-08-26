import axios from "axios";

// The API client talks to the SAME origin and lets the Next.js server proxy
// /api/* to the backend (next.config.js -> rewrites(), destination BACKEND_URL).
// Baking a backend URL into the browser bundle (NEXT_PUBLIC_API_URL) breaks
// login from host browsers: "backend:8000" only resolves inside the Docker/K8s
// network.
// Remember: the web authenticates via an HttpOnly cookie set by /auth/login, so
// the client must send credentials (cookies) with every request. The Bearer token
// is NOT kept in localStorage anymore — the browser Cookie jar owns access.
export const api = axios.create({
  baseURL: "/api/v1",
  withCredentials: true,
  headers: {
    "Content-Type": "application/json",
  },
});

// The double-submit CSRF token lives in a NON-HttpOnly cookie ("csrf_token") set
// at login so the SPA can read it in JS.
function readCsrfToken(): string | undefined {
  if (typeof document === "undefined") return undefined;
  const match = document.cookie
    .split(";")
    .map((c) => c.trim())
    .find((c) => c.startsWith("csrf_token="));
  return match ? match.slice("csrf_token=".length) : undefined;
}

// Attach the CSRF token header to every state-changing request (same sentinel the
// backend compares against the cookie). No localStorage token is read or written.
api.interceptors.request.use((config) => {
  const method = (config.method ?? "get").toLowerCase();
  if (["post", "put", "patch", "delete"].includes(method)) {
    const csrf = readCsrfToken();
    if (csrf) {
      config.headers["X-CSRF-Token"] = csrf;
    }
  }
  return config;
});

// Response interceptor for errors.
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      const url: string = error.config?.url ?? "";
      // A failed login attempt must NOT hard-redirect: the login form itself
      // displays the error banner. There is also no "/login" route in this SPA.
      if (!url.includes("/auth/login") && !url.includes("/auth/me")) {
        if (typeof window !== "undefined" && window.location.pathname !== "/") {
          window.location.href = "/";
        }
      }
    }
    return Promise.reject(error);
  }
);
