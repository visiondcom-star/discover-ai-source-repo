"use client";

import { useContext } from "react";
import { useTenant as useTenantContext } from "@/components/TenantProvider";

export function useTenant() {
  return useTenantContext();
}
