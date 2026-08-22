# AI Destination OS — Projektkontext für Claude Code

## Aktueller Stand (bitte zuerst lesen)

Dieses Repo ist kein leeres Grundgerüst — es enthält bereits einen **echten,
getesteten Teil** der Plattform. Bitte vor jeder neuen Aufgabe kurz prüfen, was
schon existiert, statt etwas doppelt zu bauen:

| Teil | Status | Details |
|---|---|---|
| Backend (FastAPI) | ✅ Fertig & getestet | **73/73 pytest-Tests grün** (`docker compose exec backend pytest tests/ -v`; von frischem Postgres-Volume aus verifiziert, inkl. RAG-Pfad). Auth, Tenants, POIs (inkl. Delete), Trips, Chat mit echtem RAG (pgvector-Similarity-Search über `pois.embedding`), Content-Pipeline, Analytics, Booking-Agent mit Consent-Flow, **Review-Flow (CRUD + Aggregat-Automatisierung)**, **CV-Vision über denselben Provider-Pfad wie Chat/RAG**, **Constraint-Solver (17 Tests)** — siehe Prinzip 6. **Review-Modell & Aggregat-Sync** (`app/models.py` + `app/services/review_service.py`): tenant-skopiertes Rating/Comment pro POI, `UniqueConstraint("tenant_id", "user_id", "poi_id")` verhindert Mehrfach-Reviews; `POI.average_rating`/`review_count` werden bei jedem Create/Update/Delete via `recompute_poi_rating()` aktuell gehalten und über die API exponiert (`app/api/v1/endpoints/reviews.py`, 7 Tests). **Bugfix:** `User`-E-Mail-Eindeutigkeit pro Tenant war zuvor nur ein SQL-Kommentar ohne Wirkung, jetzt eine echte `UniqueConstraint("tenant_id", "email")` — durch `test_users.py` (2 Tests) abgesichert. Alle `datetime.utcnow`-Defaults laufen jetzt über eine benannte `utcnow()`-Hilfsfunktion (vermeidet das SQLAlchemy-Fallstrick, einen Zeitpunkt einmalig beim Modul-Import statt bei jedem Insert zu berechnen). **LLM-Provider-Architektur inkl. Embeddings & Vision** (Prinzip 7): `app/services/llm_providers/` mit `LLMProvider`-Base (`complete()`, `embed()`, `identify_image()`), `OpenAIProvider`, `MockProvider` (deterministisches Fake-Embedding und -Vision, kein Netzwerk-Call), `get_llm_provider()`-Factory. CV (`/cv/identify`) ist auf diesen Provider-Pfad migriert via `app/services/cv_service.py` — echte OpenAI-Vision mit API-Key, sonst deterministischer Mock (3 Tests in `test_cv.py`). Aktivierung über `LLM_PROVIDER=openai` + `OPENAI_API_KEY` in `backend/.env` (nicht versioniert) — ohne beides läuft alles deterministisch im Mock-Modus. RAG zusätzlich gated über `USE_PGVECTOR` (Default `false`). `deploy/postgres/init-test-db.sql` aktiviert die `vector`-Extension beim ersten Volume-Init — **Postgres-Image muss nach Änderungen an diesem Script neu gebaut werden** (`docker compose build postgres`), sonst bleibt die alte Version im Image. **Hinweis Testcount:** real 73 Testfunktionen (inkl. `test_reviews.py` 7 und `test_cv.py` 3; RAG wird indirekt über `test_chat.py` mitgetestet). **Schema-Hinweis:** `Review`-Tabelle und neue Spalten auf `POI`/`User` erfordern bei bestehenden Daten eine echte Migration (Alembic) statt `create_all` — in Dev/Test unkritisch, da Volumes bei Schema-Änderungen neu erstellt werden. |
| Frontend (Next.js) | ✅ Fertig & E2E-getestet | **13/13 Playwright-E2E-Tests grün** (`docker compose --profile test run --rm playwright`) — Landing-Page, Login/Register-Flow, Demo-Login, alle 5 Tabs (Home/Explorer/Réservations/Assistant/Profil), Logout, Fehlerbehandlung bei ungültigem Token. Single-Page-App mit genau einer Next.js-Route (`/`), Tabs über React-State in `AppShell.tsx`. `next.config.js` proxied `/api/*` serverseitig zum Backend (Rewrite, konfigurierbar über `BACKEND_URL`). **Sicherheit:** `next` auf `14.2.35` gepatcht (kritische Cache-Poisoning-Lücke behoben, kein Breaking Change innerhalb 14.x), ungenutztes `next-intl` entfernt. **Bekannte Restrisiken:** 8 `high`-Findings in `npm audit` — `glob`/`minimatch`/`eslint-config-next` sind reine Dev-/Lint-Dependencies (kein Produktionsrisiko); der Rest erfordert einen Major-Sprung auf `next@16.x` (überspringt v15, Breaking Change) — bewusst zurückgestellt, bis eine eigene Session mit vollständigem Retest von `next.config.js`-Rewrite und `middleware.ts` eingeplant ist. |
| Mobile (Flutter) | ✅ Fertig & getestet | `flutter_app/`-Duplikat entfernt (war leeres Default-Scaffold). `mobile/` ist die einzige, produktiv verifizierte Variante: `flutter pub get` erfolgreich, **14/14 Flutter-Tests grün** (`cd mobile && flutter test`). 1464 Zeilen echter Dart-Code in `lib/{models,providers,screens,widgets,services}`. 
| Docker / Docker Compose | ✅ Fertig & getestet | `docker-compose.yml` (Postgres+PostGIS+pgvector, Redis, Backend, Frontend, Playwright unter `profiles: ["test"]`) läuft durch. **Backend-Tests sind als Bind-Mount verdrahtet** (`./backend/tests:/app/tests`), `TEST_DATABASE_URL` zeigt auf `discoverai_test`, das per Init-Script (`deploy/postgres/init-test-db.sql`) bei frischem Volume automatisch angelegt wird. `docker compose exec backend pytest tests/ -v` funktioniert damit exakt wie dokumentiert. |
| Kubernetes-Manifeste | ✅ Vorhanden | `deploy/k8s/` existiert (namespace, postgres, redis, backend, frontend, ingress, secrets, HPA, Kustomize + Overlays staging/production). Nicht deployt-up-to-date verifiziert. |
| CI/CD (GitHub Actions) | ✅ Vorhanden | `.github/workflows/ci.yml` existiert (backend pytest + frontend build/lint/Playwright + flutter tests + docker build). Nicht in dieser Session ausgeführt. |
| LLM/CV-Anbindung | ✅ Abstrahiert & produktiv verifiziert | **LLM-Provider-Abstraktion inkl. RAG & Vision fertig** (siehe Backend-Zeile) — echte OpenAI-Chat-, Embedding- und Vision-Calls laufen bestätigt gegen `demo@algeria.travel` (backend-seitig pytest; Chat zusätzlich E2E Playwright grün, 13/13). CV: `app/api/v1/endpoints/cv.py` (`identify_object`, `get_ar_assets`, `get_nearby_ar`) ist jetzt auf denselben Provider-Pfad wie Chat/RAG migriert via `app/services/cv_service.py` + `identify_image()` im Provider-Interface — echte Vision mit API-Key, sonst deterministischer Mock. |

**⚠️ Arbeitsverzeichnis:** Dieses Verzeichnis ist **bereits ein Git-Repository** (Branch `main`, Stand `1ac6745`). Der unversionierte Stand aus früheren Sessions wurde inzwischen eingecheckt. Änderungen bitte committen, nicht nur lokal lassen.

**Bekannte, in dieser Session behobene Bugs (zur Referenz, falls sie in einer nicht synchronisierten Kopie erneut auftauchen):**
- `backend/app/api/v1/endpoints/analytics.py`: `active_today.scalar()` wurde zweimal auf demselben Result-Objekt aufgerufen → `ResourceClosedError`. Fix: Wert einmal lesen und wiederverwenden.
- `backend/app/api/v1/endpoints/chat.py`: Route war `@router.post("")` → 307-Redirect bei `POST /api/v1/chat/`; Tests erreichten den Chat-Service nie. Fix: `@router.post("/")`.
- `backend/app/api/v1/endpoints/content.py`: `poi_ids: list` (bare Annotation) → 422 bei `/content/validate`. Fix: `List[UUID] = Body(...)`.
- `backend/app/api/v1/endpoints/tenants.py`: `/tenants/current` las `slug` als Query-Param statt aus `X-Tenant-Slug`-Header → gab immer `algeria` zurück. Fix: Header-Lesen.
- `backend/app/services/trip_planner.py`: `generate_trip` gab `Trip` ohne eager-load `items` zurück → `MissingGreenlet` bei Response-Serialisierung. Fix: `selectinload(Trip.items).selectinload(TripItem.poi)`.
- `backend/tests/conftest.py`: Test-Harness war im Docker-Kontext kaputt — (a) `TEST_DATABASE_URL` zeigte auf `localhost:5432` (im Container unerreichbar), (b) asyncpg-Connections über Event-Loops hinweg (`NullPool` fehlte), (c) App nutzte für Tenant-Lookups (`get_tenant_from_header`) die Prod-Engine statt der Test-DB, (d) keine Test-Isolation → Duplikate `test-tenant`. Fix: NullPool, Routing aller `AsyncSessionLocal` auf Test-DB, per-Test-Schema-Reset + `algeria`-Seed.
- `backend/tests/*`: 5 veraltete Assertions erwarteten `403` bei fehlenden Credentials; App liefert korrekt `401` (RFC 7235). Auf `401` korrigiert.
- `frontend/src/app/page.tsx`: `useAuth()` mit falschem Property-Namen destrukturiert (`isLoading` statt `loading`) — TS-Build-Fehler.
- `frontend/next.config.js`: API-Rewrite-Destination war fest auf `http://localhost:8000` verdrahtet — im Docker-Netzwerk unerreichbar. Jetzt konfigurierbar über `process.env.BACKEND_URL`.
- `docker-compose.yml`: Playwright brauchte anonymen Volume-Mount für `/app/node_modules`.

**Empfohlene Reihenfolge für die nächsten Schritte:**
1. ~~Docker Compose (dev) schreiben + Backend-/Frontend-Dockerfile bauen und testen~~ ✅ erledigt
2. ~~Frontend-Rendering im echten Browser verifizieren~~ ✅ erledigt — 13/13 Playwright-Tests grün
3. ~~LLM-Provider-Architektur (Base/OpenAI/Mock/Factory)~~ ✅ erledigt — 61/61 Backend-Tests grün, dokumentierter Docker-Befehl verifiziert
4. ~~Flutter-Duplikat auflösen~~ ✅ erledigt — `flutter_app/` entfernt, `mobile/` verifiziert (14/14 Tests grün)
5. **CI-Pipeline real laufen lassen** (`.github/workflows/ci.yml` existiert, aber nicht in dieser Session ausgeführt) — pytest lokal grün, Playwright lokal grün
6. Kubernetes-Manifeste deployen/testen (existieren, aber unverifiziert)
7. Echten LLM-/CV-Provider hinter die bestehenden Abstraktionen hängen (`OPENAI_API_KEY` setzen → Factory wählt `OpenAIProvider`)

**Hinweis zur Pflege dieser Tabelle:** Der Testcount ist real **61**, nicht 78 — die 17 fehlenden Tests (RAG/Context/CV) existieren in dieser Repo-Kopie schlicht nicht als Dateien. Bitte vor größeren Sessions kurz gegenchecken, ob die Tabelle noch mit der Realität übereinstimmt.

Ausführliche Architektur-Begründung: siehe `docs/architektur.md`.

---

## Was dieses Projekt ist

Ein KI-gestütztes Destination Operating System für den Tourismussektor: persönlicher Reiseberater (Planung, CV/AR-Vor-Ort-Guide, Live-Kontext, Buchungsagent) plus B2G-Dashboard für Hotels/Behörden/Tourismusbüros. Von Beginn an als **internationale Multi-Tenant-/White-Label-Plattform** konzipiert, nicht als Einzelmarkt-App.

Vollständige Architektur: siehe `docs/architektur.md` (aus dem Strategiedokument übernommen).

## Nicht verhandelbare Architekturprinzipien

Diese Regeln gelten für **jede** Änderung, unabhängig davon, wie klein die Aufgabe wirkt:

1. **Kein länder- oder kundenspezifischer Code im Kern.** Alles, was sich zwischen Märkten/Tenants unterscheidet (Branding, Sprache, Zahlungsanbieter, Feature-Umfang, Content), ist **Konfiguration oder Daten**, niemals ein `if country == "DZ"` im Kerncode. Wenn eine Aufgabe das nahelegt, zuerst zurückfragen statt zu implementieren.
2. **`tenant_id` auf allen Kernentitäten.** User, Bookings, Sessions, Konfigurationsobjekte — jede neue Tabelle/jedes neue Model bekommt von Anfang an ein Tenant-Feld, auch wenn aktuell nur ein Tenant existiert.
3. **RAG-Wissensbasis strikt pro Tenant getrennt.** Kein gemeinsamer Vektorindex über mehrere Länder/Kunden hinweg — sonst sickert Kontext aus Markt A in Anfragen aus Markt B.
4. **Externe Anbieter nur über einen Adapter-Layer.** Karten, Buchungssysteme, Zahlungsanbieter, Wetter-/Verkehrsdaten — jede Integration bekommt ein Interface, hinter dem der konkrete Anbieter austauschbar ist. Kein direkter Aufruf einer Drittanbieter-API aus der Kernlogik.
5. **Booking-Agent strikt getrennt von Empfehlungslogik.** Jede Aktion mit finanzieller/vertraglicher Wirkung (Buchung, Kauf, Stornierung) braucht einen expliziten Consent-Schritt im Flow — niemals eine stille Automatisierung, auch wenn das technisch möglich wäre.
6. **Harte Constraints (Öffnungszeiten, Budget, Distanzen) laufen über einen Solver/Regel-Layer, nicht über das LLM.** Das LLM schlägt vor und formuliert; die Einhaltung harter Zahlen prüft deterministischer Code.
7. **Modellagnostische Provider-Abstraktion für LLM/CV/TTS.** Kein direkter, fest verdrahteter Aufruf eines einzelnen Anbieters in der Kernlogik — Provider ist austauschbar.
8. **Emotionale/Zustandssignale nur aus expliziter, granularer Nutzerzustimmung.** Keine implizite Verhaltens- oder Biometrie-Auswertung ohne gesonderten Consent.

## Tech-Stack (Referenz)

- **Frontend:** Flutter (iOS, Android, Web) mit Theming/Feature-Flags pro Tenant
- **Backend:** FastAPI oder NestJS (Entscheidung projektabhängig, konsistent halten)
- **Datenbank:** PostgreSQL + PostGIS; Vektorindex pro Tenant (z. B. pgvector)
- **Event-Bus:** für Live-Kontext-Daten (Wetter, Verkehr, Events) — kein synchrones Ketten-Polling
- **Objektspeicher:** S3-kompatibel für Bilder/3D-Assets/Audioguides
- **Karten/Routing:** OpenStreetMap/GraphHopper als lizenzunabhängige Basis, Google Maps optional pro Tenant
- **Deployment:** containerisiert, cloud-agnostisch (Kubernetes), Region-Deployment möglich

## Wie mit Aufgaben umgehen

- Vor größeren Änderungen: kurz prüfen, ob die Aufgabe eines der Prinzipien oben berührt — falls ja, das explizit im Vorschlag benennen, nicht stillschweigend umgehen.
- Neue Datenquellen/Anbieter: immer als Adapter mit klarem Interface anlegen, auch wenn aktuell nur ein Anbieter existiert.
- Bei Unsicherheit, ob etwas Kernlogik oder Tenant-Konfiguration ist: im Zweifel als Konfiguration behandeln — das ist der teurere Fehler, wenn er andersherum passiert.
- Tests für Tenant-Isolation (Daten aus Tenant A dürfen nie in Tenant B sichtbar sein) sind Pflichtbestandteil, nicht optional.

## Phasenrahmen

| Phase | Fokus |
|---|---|
| 1 — MVP | Trip Planning + Content für 1 Pilotmarkt, Multi-Tenant-Grundgerüst steht |
| 2 | CV/AR-Guide, Live-Context-Engine |
| 3 | Booking-Agent, B2G-Dashboard |
| 4 | Weitere Länder/Tenants — reines Onboarding (Content + Config), keine Kernentwicklung |

Lackmustest: Wenn Phase 4 eine Code-Änderung statt nur Konfiguration/Content braucht, war die Trennung in einer früheren Phase nicht sauber genug — das ist ein Signal, die Architektur zu überprüfen, nicht einfach weiterzumachen.
