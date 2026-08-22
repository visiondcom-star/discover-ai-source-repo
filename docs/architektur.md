# Architecture — Discover AI (AI Destination OS)

> **État réel au 22.08.2026** — après premier déploiement de production locale (HTTPS via Traefik).
> Backend : **73/73** pytest · Frontend : **13/13** Playwright E2E · Mobile : **14/14** Flutter.

---

## 1. Vue d'ensemble du système

Plateforme de voyage multi-tenant avec IA : planification de voyages, chat RAG sur la base
de connaissances POI, reviews, vision par ordinateur (CV/AR), booking-agent avec
consentement explicite.

```
                 ┌────────────────────────────────────────────────────────┐
   Navigateur    │                  Hôte (macOS / VPS)                    │
 ──HTTPS:443───▶ │   Traefik v2.11 (reverse proxy + TLS termination)      │
                 │     ├─ Host(localhost)      ──▶  frontend  (:3000)     │
                 │     └─ Host(api.localhost)  ──▶  backend   (:8000)     │
                 │                                      │                 │
                 │            ┌─────────────────────────┤                 │
                 │      PostgreSQL 16              Redis 7                │
                 │      + PostGIS + pgvector       (cache / sessions)     │
                 └────────────────────────────────────────────────────────┘
                                        │  (LLM_PROVIDER=openai)
                                        ▼
                          OpenAI API — gpt-4o / text-embedding-3-small
                          (sinon MockProvider déterministe, hors-ligne)
```

## 2. Structure du dépôt

```
.
├── backend/                        # FastAPI (Python 3.12) — async REST API
│   ├── app/
│   │   ├── main.py                 # App FastAPI, CORS, include_router /api/v1
│   │   ├── models.py               # SQLAlchemy async (tenant_id partout)
│   │   ├── schemas.py              # Pydantic v2
│   │   ├── core/                   # Config, sécurité JWT, DB session
│   │   ├── api/v1/endpoints/       # 12 routers (voir §3.1)
│   │   └── services/
│   │       ├── llm_providers/      # Abstraction LLM/CV/Vision (§3.6)
│   │       ├── rag_service.py      # Indexation + recherche vectorielle
│   │       ├── review_service.py   # CRUD + agrégats notes POI
│   │       ├── cv_service.py       # Vision via provider path
│   │       ├── chat_service.py     # Chat avec contexte RAG
│   │       ├── trip_planner.py     # Génération d'itinéraires
│   │       └── constraint_solver.py # Contraintes dures déterministes
│   └── tests/                      # 73 tests pytest (12 fichiers)
├── frontend/                       # Next.js 16.3.2 + React 19 + Tailwind
│   ├── src/app/                    # Route unique "/" (SPA à onglets)
│   ├── src/components/AppShell.tsx # Onglets Home/Explorer/Réservations/Assistant/Profil
│   ├── src/proxy.ts                # (ex-middleware.ts)
│   ├── next.config.mjs             # Rewrite /api/* → BACKEND_URL
│   └── eslint.config.mjs           # Flat config ESLint (ex-.eslintrc.json)
├── mobile/                         # Flutter 3.16 (iOS/Android/Web), 14 tests
├── deploy/k8s/                     # Manifests Kubernetes
├── certs/                          # TLS local auto-signé (non versionné)
├── traefik-local.yml               # Config statique Traefik (TLS local)
├── docker-compose.yml              # Développement
├── docker-compose.prod.yml         # Production (VPS, placeholders)
└── docker-compose.prod.local.yml   # Override prod locale HTTPS
```

## 3. Backend — FastAPI

### 3.1 Surface API (`/api/v1`)

| Router | Préfixe | Endpoints clés |
|---|---|---|
| Auth | `/auth` | `POST /register`, `POST /login`, `GET /me` |
| Tenants | `/tenants` | `GET /current`, CRUD + config tenant |
| POIs | `/pois` | `GET /`, `GET /{id}`, `DELETE /{id}` |
| **Reviews** | `/pois` | `POST /{poi_id}/reviews` (201), `GET /{poi_id}/reviews`, `GET/PATCH/DELETE /{poi_id}/reviews/{review_id}` |
| Trips | `/trips` | `POST /generate`, `GET /` |
| Chat | `/chat` | `POST /` — LLM + contexte RAG |
| RAG | `/rag` | `POST /index`, `POST /search` |
| Content | `/content` | `POST /import/csv`, `POST /import/json` |
| Context | `/context` | `GET /weather`, `GET /events` |
| Analytics | `/analytics` | `POST /track`, `GET /dashboard/overview` |
| Bookings | `/bookings` | CRUD + consent-flow explicite |
| CV/AR | `/cv` | `POST /identify`, `GET /ar/poi/{id}`, `GET /ar/nearby` |

### 3.2 Multi-Tenancy

- Isolation hybride : base PostgreSQL partagée, **`tenant_id` sur toutes les entités cœur**
  (users, POIs, trips, bookings, reviews…).
- Header `X-Tenant-Slug` (défaut : `algeria`) résolu par dépendance FastAPI.
- Unicité e-mail **par tenant** : `UniqueConstraint("tenant_id", "email")` sur `User`
  (bugfix récent — auparavant simple commentaire SQL sans effet ; sécurisé par `test_users.py`).
- Defaults temporels via helper nommé `utcnow()` — évite le piège SQLAlchemy d'un timestamp
  figé calculé une seule fois à l'import du module.

### 3.3 Pipeline RAG (état réel)

1. **Indexation** — `POST /rag/index` : découpe des contenus, embeddings via
   `provider.embed()`, stockage vectoriel dans `pois.embedding` (**pgvector**).
2. **Recherche** — similarité cosinus pgvector, **strictement scopée par `tenant_id`**
   (aucune fuite inter-tenants — principe non négociable n°3).
3. **Chat** — `POST /chat` : question → embedding → top-k POIs pertinents injectés dans
   le prompt → réponse formulée par le LLM (`gpt-4o`).
4. **Gating** : activé par `USE_PGVECTOR=true`. Sans clé API ni pgvector, tout tourne en
   mode **MockProvider déterministe** (embeddings fake stables, zéro appel réseau).

Vérifié en conditions réelles : indexation fraîche depuis un volume Postgres vierge,
chemin RAG complet couvert par les tests (`test_chat.py`, `test_content_pipeline.py`).
Smoke test production locale : appel OpenAI réel effectué, fallback gracieux OK.

### 3.4 Système de Reviews (nouveau)

- Modèle `Review` scopé tenant : rating + commentaire par utilisateur et par POI.
  `UniqueConstraint("tenant_id", "user_id", "poi_id")` empêche les reviews multiples.
- **Synchronisation des agrégats** : `recompute_poi_rating()` (dans
  `app/services/review_service.py`) met à jour `POI.average_rating` / `POI.review_count`
  à chaque create / update / delete — jamais de compteur dérivant.
- Exposition API : les agrégats sont renvoyés avec les POIs (`GET /pois`).
- Couverture : **7 tests** (`test_reviews.py`).

### 3.5 Vision par ordinateur / AR

- `POST /cv/identify` : identification d'un monument/POI depuis une image.
- `GET /cv/ar/poi/{id}`, `GET /cv/ar/nearby` : assets AR par POI / à proximité.
- Implémentation dans `app/services/cv_service.py`, **sur le même chemin provider que
  Chat/RAG** (`identify_image()` de l'interface `LLMProvider`) — vraie vision OpenAI si
  clé API présente, sinon mock déterministe. **3 tests** (`test_cv.py`).

### 3.6 Abstraction LLM Provider (principe n°7)

```
app/services/llm_providers/
├── base.py          # LLMProvider : complete() / embed() / identify_image()
├── openai.py        # OpenAIProvider (réseau réel)
├── mock.py          # MockProvider (déterministe, hors-ligne, testable)
└── factory          # get_llm_provider() ← env LLM_PROVIDER
```

| Variable | Valeur | Effet |
|---|---|---|
| `LLM_PROVIDER` | `openai` \| *(défaut mock)* | Active le réseau réel |
| `OPENAI_API_KEY` | `sk-…` | Requis pour openai (`backend/.env`, non versionné) |
| `OPENAI_MODEL` | `gpt-4o` | Modèle de complétion |
| `EMBEDDING_MODEL` | `text-embedding-3-small` | Modèle d'embedding |
| `USE_PGVECTOR` | `true` | Active la recherche vectorielle réelle |

Aucun appel direct à un fournisseur dans la logique métier — tout passe par l'interface.

### 3.7 Constraint Solver

Les contraintes dures (horaires d'ouverture, budget, distances) sont vérifiées par du
**code déterministe** (`constraint_solver.py`, **17 tests** dédiés), jamais déléguées au
LLM. Le LLM propose et formule ; le solver garantit les chiffres (principe n°6).

### 3.8 Booking-Agent & Consentement

Toute action à effet financier/contractuel (réservation, achat, annulation) exige une
étape de consentement explicite (`/bookings/{id}/consent`). Aucune automatisation
silencieuse (principe n°5). Le booking-agent est strictement séparé de la logique de
recommandation.

## 4. Frontend — Next.js 16

- **Next.js 16.3.2 + React 19 + Tailwind CSS**, build Turbopack.
- Migration majeure v14 → v16 (saute v15) : `next.config.mjs`, ESLint flat config
  (`eslint.config.mjs`, remplace `.eslintrc.json`), `middleware.ts` → `proxy.ts`.
  Les findings `high` de `npm audit` sont résolus par l'upgrade.
- **SPA à route unique `/`** : les 5 onglets (Home / Explorer / Réservations / Assistant /
  Profil) sont gérés par React-State dans `AppShell.tsx`.
- Proxy API : `next.config.mjs` rewrrote `/api/*` vers le backend via `BACKEND_URL`
  (aucun CORS à gérer côté navigateur).
- **13/13 Playwright E2E verts** : landing, login/register, demo-login, les 5 onglets,
  logout, gestion d'un token invalide.

## 5. Mobile — Flutter

- `mobile/` est l'unique variante (le doublon `flutter_app/` vide a été supprimé).
- ~1464 lignes de Dart dans `lib/{models,providers,screens,widgets,services}`,
  cartes via `flutter_map`, **14/14 tests verts** (`cd mobile && flutter test`).

## 6. Modèle de données (tables clés)

Toutes portent `tenant_id` :

| Table | Points marquants |
|---|---|
| `tenants` | branding, langues, RTL, providers de paiement, feature flags |
| `users` | `UniqueConstraint(tenant_id, email)`, rôles |
| `pois` | géométrie PostGIS, colonne `embedding` (pgvector), `average_rating`, `review_count` |
| `reviews` | `UniqueConstraint(tenant_id, user_id, poi_id)` |
| `trips` / items | itinéraires générés (LLM + solver) |
| `bookings` | workflow de consentement |
| analytics/events | tracking produit |

## 7. Déploiements

### 7.1 Développement
```bash
docker compose up --build
# frontend http://localhost:3000 · API http://localhost:8000/docs
```

### 7.2 Production locale HTTPS — **déployée et smoke-testée** ✅

```bash
cp .env.production.example .env.production   # puis remplir les secrets
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/localhost.key -out certs/localhost.crt \
  -subj "/CN=localhost/O=Discover AI"

docker compose --env-file .env.production \
  -f docker-compose.prod.yml -f docker-compose.prod.local.yml up -d --build
```

- Entrées : **https://localhost** (frontend) et **https://api.localhost** (API + `/docs`),
  TLS terminé par Traefik v2.11 avec le certificat auto-signé de `certs/`.
- Config statique : `traefik-local.yml` (entrypoints `web :80` / `websecure :443`,
  provider Docker avec `exposedByDefault: false`, dashboard activé via `api.insecure`;
  publier `- "8080:8080"` pour y accéder depuis l'hôte).
- Smoke test réalisé : health `{"status":"healthy"}`, login démo, `/me`, liste POIs
  (Casbah d'Alger…), chat RAG avec appel OpenAI réel et fallback gracieux.
- Arrêt : `docker compose -f docker-compose.prod.yml -f docker-compose.prod.local.yml down`

### 7.3 VPS (prêt — placeholders à remplacer)
`docker-compose.prod.yml` + Traefik + Let's Encrypt : remplacer `your-domain.com`,
`api.your-domain.com`, `admin@your-domain.com`, puis renseigner `.env.production`.

### 7.4 Kubernetes
Manifests dans `deploy/k8s/` : namespace → secrets → postgres → redis → backend →
frontend → ingress TLS.

## 8. Stratégie de tests

| Suite | Commande | État |
|---|---|---|
| Backend pytest | `docker compose exec backend pytest tests/ -v` | **73/73** ✅ |
| Playwright E2E | `docker compose --profile test run --rm playwright` | **13/13** ✅ |
| Flutter | `cd mobile && flutter test` | **14/14** ✅ |

Répartition backend : analytics 8 · constraint-solver 17 · content-pipeline 8 · pois 7 ·
reviews 7 · auth 5 · bookings 5 · tenants 4 · trips 4 · chat 3 · cv 3 · users 2 = **73**.

Les tests d'isolation tenant (données du tenant A invisibles du tenant B) font partie
intégrante de la suite backend — obligatoires pour toute nouvelle entité.

## 9. Principes d'architecture non négociables

1. **Aucun code pays/client dans le noyau** — tout écart entre marchés est configuration ou données.
2. **`tenant_id` sur toute entité cœur**, dès la première table.
3. **RAG strictement séparé par tenant** — aucun index vectoriel partagé.
4. **Fournisseurs externes uniquement derrière un adapter layer** (interface + implémentations).
5. **Booking-Agent séparé de la recommandation** — consentement explicite obligatoire.
6. **Contraintes dures via solver déterministe**, pas via le LLM.
7. **Abstraction provider agnostique du modèle** pour LLM/CV/TTS.
8. **Signaux émotionnels/état uniquement après consentement granulaire explicite.**

*Test décisif (Phase 4)* : si l'ajout d'un nouveau pays exige un changement de code plutôt
qu'un simple onboarding (config + contenu), c'est le signal qu'une séparation a mal été
faite — il faut revoir l'architecture, pas continuer.