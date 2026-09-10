"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Tenant } from "@/types";

const TenantContext = createContext<Tenant | null>(null);

export function TenantProvider({ children }: { children: React.ReactNode }) {
  const [tenant, setTenant] = useState<Tenant | null>(null);

  useEffect(() => {
    api.get<Tenant>("/tenants/current").then((res) => {
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
