import type { Metadata } from "next";
import "./globals.css";
import { TenantProvider } from "@/components/TenantProvider";

export const metadata: Metadata = {
  title: "Discover AI",
  description: "AI Destination OS — Multi-Tenant Travel Platform",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr">
      <body>
        <TenantProvider>
          {children}
        </TenantProvider>
      </body>
    </html>
  );
}
