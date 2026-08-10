import axios from "axios";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://backend:8000";
const DEFAULT_TENANT = process.env.NEXT_PUBLIC_DEFAULT_TENANT || "algeria";

export const api = axios.create({
  baseURL: `${API_URL}/api/v1`,
  headers: {
    "Content-Type": "application/json",
    "X-Tenant-Slug": DEFAULT_TENANT,
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
      if (typeof window !== "undefined") {
        localStorage.removeItem("token");
        window.location.href = "/login";
      }
    }
    return Promise.reject(error);
  }
);
