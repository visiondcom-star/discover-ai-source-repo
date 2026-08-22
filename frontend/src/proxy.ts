import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { TENANT_SLUG } from "@/lib/tenant";

export function proxy(request: NextRequest) {
  // Add tenant header to all requests
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-tenant-slug", TENANT_SLUG);

  return NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });
}

export const config = {
  matcher: "/api/:path*",
};
