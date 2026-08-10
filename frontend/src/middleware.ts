import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  // Add tenant header to all requests
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-tenant-slug", "algeria");

  return NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });
}

export const config = {
  matcher: "/api/:path*",
};
