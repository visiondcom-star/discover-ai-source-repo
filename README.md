# Discover AI — AI Destination OS

Multi-Tenant International Travel Platform built with FastAPI, Next.js, Flutter, PostgreSQL, and OpenAI.

> **Status**: Backend **73/73 pytest** · Frontend **13/13 Playwright E2E** · Mobile **14/14 Flutter** · First real deployment (local HTTPS production) verified ✅

## Architecture

- **Backend**: FastAPI (Python 3.12) — Async REST API with 60+ endpoints, 12 routers
- **Frontend**: Next.js 16 + React 19 + Tailwind CSS — SPA with tab navigation
- **Mobile**: Flutter 3.16 — iOS + Android + Web
- **Database**: PostgreSQL 16 + PostGIS + pgvector (per-tenant vector indexes)
- **Cache**: Redis 7
- **AI**: OpenAI gpt-4o + text-embedding-3-small — behind a swappable provider abstraction (real OpenAI or deterministic offline MockProvider)
- **Reverse proxy / TLS**: Traefik v2.11
- **Maps**: Leaflet (Web) / flutter_map (Mobile)
- **Auth**: JWT with tenant isolation
- **Deploy**: Docker Compose (dev + prod) + Kubernetes

Full details: [docs/architektur.md](docs/architektur.md)

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Git
- (Optional) OpenAI API key — without it everything runs deterministically offline (MockProvider)

### Development
```bash
# 1. Clone
git clone <repo-url> ai-destination-os
cd ai-destination-os

# 2. Configure
cp .env.example .env
# Edit .env and add OPENAI_API_KEY + LLM_PROVIDER=openai for real AI features

# 3. Launch
docker compose up --build

# 4. Access
# Frontend: http://localhost:3000
# API:      http://localhost:8000
# API Docs: http://localhost:8000/docs
```

### Local Production (HTTPS via Traefik) — verified deployment
```bash
# 1. Configure secrets
cp .env.production.example .env.production
# Fill: DB_PASSWORD, SECRET_KEY, DOMAIN, OPENAI_API_KEY

# 2. Generate self-signed TLS cert (local only)
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/localhost.key -out certs/localhost.crt \
  -subj "/CN=localhost/O=Discover AI"

# 3. Launch stack behind Traefik
docker compose --env-file .env.production \
  -f docker-compose.prod.yml -f docker-compose.prod.local.yml up -d --build

# 4. Access (browser warning expected: self-signed certificate → Accept)
# Frontend: https://localhost
# API Docs: https://api.localhost/docs
```

Stop: `docker compose -f docker-compose.prod.yml -f docker-compose.prod.local.yml down`

### Demo Credentials
- **Email**: `demo@algeria.travel`
- **Password**: `demo1234`
- **Tenant**: `algeria` (X-Tenant-Slug header)

## API Endpoints (60+)

| Module | Endpoints |
|--------|-----------|
| Auth | `/api/v1/auth/register`, `/api/v1/auth/login`, `/api/v1/auth/me` |
| Tenants | `/api/v1/tenants/current`, `/api/v1/tenants/` |
| POIs | `/api/v1/pois/`, `/api/v1/pois/{id}` |
| Trips | `/api/v1/trips/generate`, `/api/v1/trips/` |
| Chat (RAG-powered) | `/api/v1/chat/` |
| RAG | `/api/v1/rag/index`, `/api/v1/rag/search` (pgvector similarity, per-tenant) |
| **Reviews** | `/api/v1/pois/{poi_id}/reviews` — POST/GET list; PATCH/DELETE per review; aggregates auto-synced to `POI.average_rating` / `review_count` |
| Content | `/api/v1/content/import/csv`, `/api/v1/content/import/json` |
| Context | `/api/v1/context/weather`, `/api/v1/context/events` |
| Analytics | `/api/v1/analytics/track`, `/api/v1/analytics/dashboard/overview` |
| Bookings | `/api/v1/bookings/`, `/api/v1/bookings/{id}/consent` |
| CV/AR | `/api/v1/cv/identify`, `/api/v1/cv/ar/poi/{id}`, `/api/v1/cv/ar/nearby` |

## Testing

### Backend (73 pytest tests)
```bash
docker compose exec backend pytest tests/ -v
# or locally:
cd backend && pytest tests/ -v --cov=app
```

### Frontend E2E (13 Playwright tests)
```bash
docker compose --profile test run --rm playwright
```

### Mobile (14 Flutter tests)
```bash
cd mobile && flutter test
```

## Deployment

### Local Production HTTPS (current, verified ✅)
Traefik v2.11 terminates TLS with a self-signed cert (`certs/`) →
frontend `https://localhost`, API `https://api.localhost/docs`.
See [Quick Start → Local Production](#local-production-https-via-traefik--verified-deployment).

Smoke-tested live: healthcheck healthy, demo login, `/me`, POIs listing, RAG chat (real OpenAI call, graceful fallback).

### VPS Production (Docker Compose + Traefik + Let's Encrypt)
```bash
cp .env.production.example .env.production
# Fill: DB_PASSWORD, SECRET_KEY, DOMAIN, OPENAI_API_KEY
# Replace placeholders: your-domain.com, api.your-domain.com, admin@your-domain.com
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
```

### Production (Kubernetes)
```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/secrets.yaml
kubectl apply -f deploy/k8s/postgres.yaml
kubectl apply -f deploy/k8s/redis.yaml
kubectl apply -f deploy/k8s/backend.yaml
kubectl apply -f deploy/k8s/frontend.yaml
kubectl apply -f deploy/k8s/ingress.yaml
```

### Flutter Build
```bash
cd mobile
flutter pub get
flutter test
flutter build apk --release    # Android
flutter build ios --release      # iOS
flutter build web --release      # Web
```

## Project Structure

```
.
├── backend/            # FastAPI application
│   ├── app/
│   │   ├── main.py
│   │   ├── models.py   # tenant_id on every core table
│   │   ├── schemas.py
│   │   ├── api/v1/endpoints/   # auth, tenants, pois, reviews, trips, chat,
│   │   │                       # rag, content, context, analytics, bookings, cv
│   │   ├── services/           # llm_providers/, rag, reviews, cv, chat, solver…
│   │   └── core/
│   └── tests/          # 73 pytest tests
├── frontend/           # Next.js 16 application
│   ├── src/
│   │   ├── app/        # single route "/", tabs in AppShell.tsx
│   │   ├── components/
│   │   ├── lib/
│   │   └── proxy.ts
│   ├── next.config.mjs # proxies /api/* → BACKEND_URL
│   └── eslint.config.mjs
├── mobile/             # Flutter application (14 tests)
├── docs/architektur.md # detailed architecture documentation
├── deploy/k8s/         # Kubernetes manifests
├── traefik-local.yml   # Traefik static config (local TLS)
├── certs/              # self-signed TLS certs (gitignored)
├── docker-compose.yml            # development
├── docker-compose.prod.yml       # production (VPS placeholders)
└── docker-compose.prod.local.yml # local prod override (HTTPS on localhost)
```

## Multi-Tenant Architecture

The platform uses a **hybrid tenant isolation model**:
- Shared PostgreSQL database with `tenant_id` on all core tables
- Separate vector index per tenant for RAG (prevents cross-tenant knowledge leakage)
- Per-tenant configuration: branding, languages, RTL, payment providers, feature flags

Adding a new country requires **zero code changes**:
1. Create tenant via API (config only)
2. Import POIs via CSV/JSON (content only)
3. Index knowledge base

## License

MIT
