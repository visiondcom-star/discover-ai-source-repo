import { defineConfig, devices } from '@playwright/test';

/**
 * ANNAHME: Ich kenne den Inhalt von frontend/package.json, frontend/app/**
 * (Routen, Komponenten, data-testid o.ä.) nicht — daher testen die Specs in
 * tests/e2e/ bewusst nur auf einer generischen Ebene (Seite lädt, kein
 * Next.js-Error-Overlay, kein leerer Body, keine Console-Errors).
 * Sobald ihr mir echte Selektoren/Testdaten gebt, verfeinere ich die Tests
 * auf konkrete Inhalte (z.B. "POI-Liste zeigt N Einträge nach RAG-Search").
 */
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? 'github' : 'list',

  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:3000',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],

  // Startet den Next.js-Dev-Server automatisch, falls nicht bereits über
  // Docker Compose erreichbar (z.B. lokal ohne Container). In CI/Docker
  // läuft der Frontend-Container bereits -> webServer wird dann übersprungen,
  // indem PLAYWRIGHT_SKIP_WEBSERVER=1 gesetzt wird (siehe README-Hinweis unten).
  webServer: process.env.PLAYWRIGHT_SKIP_WEBSERVER
    ? undefined
    : {
        // "dev" statt "start": das reale package.json-Skript wird laut
        // Scaffold-Dockerfile im Dev-Modus betrieben, nicht production-built.
        command: 'npm run dev',
        url: 'http://localhost:3000',
        reuseExistingServer: !process.env.CI,
        timeout: 60_000,
      },
});
