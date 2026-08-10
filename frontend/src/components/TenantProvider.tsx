"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { api } from "@/lib/api";

const TenantContext = createContext<any>(null);

export function TenantProvider({ children }: { children: React.ReactNode }) {
  const [tenant, setTenant] = useState<any>(null);

  useEffect(() => {
    api.get("/tenants/current").then((res) => {
      setTenant(res.data);
      document.documentElement.style.setProperty("--primary-color", res.data.primary_color);
      document.documentElement.style.setProperty("--secondary-color", res.data.secondary_color);
    }).catch(() => {
      // Use defaults
    });
  }, []);

  return (
    <TenantContext.Provider value={tenant}>
      {children}
    </TenantContext.Provider>
  );
}

export const useTenant = () => useContext(TenantContext);
