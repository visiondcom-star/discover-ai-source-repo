import { test, expect, type Page } from '@playwright/test';

/**
 * Basiert auf dem ECHTEN Code von discover-ai-source-repo(3):
 * - LandingPage.tsx: EIN Button-Paar, BEIDE führen zu <LoginForm/> (kein
 *   separates Register-Formular existiert aktuell im UI).
 * - AppShell.tsx: Tabs sind React-State (activeTab), Icons via lucide-react.
 *   Kein Tag-Filter, kein POI-Detail-Modal, keine Chat-Suggestions.
 * - useAuth.ts: Token liegt unter localStorage-Key "token" (nicht "auth_token").
 *
 * Demo-Login: demo@algeria.travel / demo1234 — Test geht davon aus, dass
 * dieser Account in der Test-DB existiert (Seed/Fixture). Falls nicht:
 * expliziter Fail mit klarer Fehlermeldung statt stillem Timeout.
 */

async function collectConsoleErrors(page: Page): Promise<string[]> {
  const errors: string[] = [];
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', (err) => errors.push(err.message));
  return errors;
}

test.describe('Landing page (nicht eingeloggt)', () => {
  test('lädt ohne Error-Overlay, zeigt CTAs', async ({ page }) => {
    const consoleErrors = await collectConsoleErrors(page);
    const response = await page.goto('/');
    expect(response?.status()).toBe(200);

    await expect(page.locator('[data-nextjs-dialog-overlay], nextjs-portal')).toHaveCount(0);
    await expect(page.getByText(/Votre voyage commence ici/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /Commencer l.aventure/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /J.ai déjà un compte/i })).toBeVisible();

    await page.waitForLoadState('networkidle');
    expect(consoleErrors, 'Console-Errors auf der Landing-Page').toEqual([]);
  });

  test('"J\'ai déjà un compte" öffnet das Login-Formular', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: /J.ai déjà un compte/i }).click();
    await expect(page.getByText(/Se connecter/i).first()).toBeVisible();
    await expect(page.getByPlaceholder('Email')).toBeVisible();
    await expect(page.getByPlaceholder('Mot de passe')).toBeVisible();
  });

  test('"Commencer l\'aventure" führt ebenfalls zum Login-Formular', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: /Commencer l.aventure/i }).click();
    await expect(page.getByPlaceholder('Email')).toBeVisible();
  });

  test('"Retour" führt zurück zur Landing-Page', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: /J.ai déjà un compte/i }).click();
    await page.getByRole('button', { name: /Retour/i }).click();
    await expect(page.getByText(/Votre voyage commence ici/i)).toBeVisible();
  });

  test('Login mit falschen Daten zeigt Fehlermeldung', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: /J.ai déjà un compte/i }).click();
    await page.getByPlaceholder('Email').fill('wrong@email.com');
    await page.getByPlaceholder('Mot de passe').fill('wrongpassword');
    await page.getByRole('button', { name: /Se connecter/i }).click();

    await expect(page.locator('.bg-red-50').first()).toBeVisible({ timeout: 10_000 });
  });
});

test.describe('App nach Login (Demo-Account)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: /J.ai déjà un compte/i }).click();
    await page.getByPlaceholder('Email').fill('demo@algeria.travel');
    await page.getByPlaceholder('Mot de passe').fill('demo1234');
    await page.getByRole('button', { name: /Se connecter/i }).click();

    const errorBanner = page.locator('.bg-red-50');
    if (await errorBanner.isVisible({ timeout: 3000 }).catch(() => false)) {
      test.fail(true, 'Demo-Login fehlgeschlagen — existiert demo@algeria.travel in der Test-DB (Seed/Fixture)?');
    }

    await expect(page.getByText(/Bonjour/i)).toBeVisible({ timeout: 10_000 });
  });

  test('Home-Tab zeigt Begrüßung ohne Console-Errors', async ({ page }) => {
    const consoleErrors = await collectConsoleErrors(page);
    await expect(page.getByText(/Bonjour/i)).toBeVisible();
    await expect(page.getByText('Discover AI')).toBeVisible();

    await page.waitForLoadState('networkidle');
    expect(consoleErrors).toEqual([]);
  });

  test('Explorer-Tab: Suche gegen Backend funktioniert ohne Console-Errors', async ({ page }) => {
    const consoleErrors = await collectConsoleErrors(page);
    await page.getByRole('button', { name: 'Explorer' }).click();

    const searchInput = page.getByPlaceholder(/Rechercher un lieu/i);
    await expect(searchInput).toBeVisible();
    await searchInput.fill('Alger');
    await searchInput.press('Enter');

    await page.waitForLoadState('networkidle');
    await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 10_000 });
    expect(consoleErrors, 'Meist: fehlgeschlagener GET /api/v1/pois/ gegen das Backend').toEqual([]);
  });

  test('Assistant-Tab: Chat-Anfrage gegen Backend funktioniert', async ({ page }) => {
    const consoleErrors = await collectConsoleErrors(page);
    await page.getByRole('button', { name: 'Assistant' }).click();
    await expect(page.getByText(/Bienvenue/i)).toBeVisible();

    const chatInput = page.getByPlaceholder(/Posez-moi une question/i);
    await chatInput.fill('Bonjour');
    await chatInput.press('Enter');

    await expect(page.locator('.chat-message')).toHaveCount(2, { timeout: 15_000 });
    await expect(page.locator('.chat-message').last()).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.chat-message').last()).not.toHaveText('Désolé, une erreur est survenue.', { timeout: 15_000 });
    expect(consoleErrors, 'Meist: fehlgeschlagener POST /api/v1/chat/ gegen das Backend').toEqual([]);
  });

  test('Réservations-Tab rendert ohne Crash', async ({ page }) => {
    await page.getByRole('button', { name: 'Réservations' }).click();
    await expect(page.getByRole('heading', { name: 'Réservations' })).toBeVisible();
  });

  test('Profil-Tab zeigt User-Email und Logout', async ({ page }) => {
    await page.getByRole('button', { name: 'Profil' }).click();
    await expect(page.getByRole('main').getByText('demo@algeria.travel')).toBeVisible();
    await expect(page.getByRole('button', { name: /Se déconnecter/i })).toBeVisible();
  });

  test('Logout funktioniert — zurück zur Landing-Page', async ({ page }) => {
    await page.getByRole('button', { name: 'Profil' }).click();
    await page.getByRole('button', { name: /Se déconnecter/i }).click();
    await expect(page.getByText(/Votre voyage commence ici/i)).toBeVisible({ timeout: 5_000 });
  });

  test('Tab-Navigation bleibt konsistent', async ({ page }) => {
    await page.getByRole('button', { name: 'Explorer' }).click();
    await expect(page.getByPlaceholder(/Rechercher un lieu/i)).toBeVisible({ timeout: 5_000 });

    await page.getByRole('button', { name: 'Réservations' }).click();
    await expect(page.getByRole('heading', { name: /Réservations/i })).toBeVisible({ timeout: 5_000 });

    await page.getByRole('button', { name: 'Assistant' }).click();
    await expect(page.getByPlaceholder(/Posez-moi une question/i)).toBeVisible({ timeout: 5_000 });

    await page.getByRole('button', { name: 'Profil' }).click();
    await expect(page.getByRole('main').getByText(/demo@algeria.travel/i)).toBeVisible({ timeout: 5_000 });

    await page.getByRole('button', { name: 'Accueil' }).click();
    await expect(page.getByText(/Bonjour/i)).toBeVisible();
  });
});

test.describe('Error Handling', () => {
  test('App zeigt keine unbehandelten Fehler bei ungültigem Token', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => {
      localStorage.setItem('token', 'invalid-token-12345');
    });
    await page.reload();
    await expect(page.locator('[data-nextjs-dialog-overlay]')).toHaveCount(0);
    await expect(page.getByText(/Votre voyage commence ici/i)).toBeVisible({ timeout: 5_000 });
  });
});