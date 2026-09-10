"use client";

import { useTenant as useTenantContext } from "@/components/TenantProvider";

export function useTenant() {
  return useTenantContext();
}
