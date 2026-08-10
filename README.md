# Discover AI — AI Destination OS

Multi-Tenant International Travel Platform built with FastAPI, Next.js, Flutter, PostgreSQL, and OpenAI.

## Architecture

- **Backend**: FastAPI (Python 3.12) — Async REST API with 60+ endpoints
- **Frontend**: Next.js 14 + React 18 + Tailwind CSS — SSR Web App
- **Mobile**: Flutter 3.16 — iOS + Android + Web
- **Database**: PostgreSQL 16 + PostGIS + pgvector
- **Cache**: Redis 7
- **AI**: OpenAI GPT-4o + text-embedding-3-small
- **Maps**: Leaflet (Web) / flutter_map (Mobile)
- **Auth**: JWT with tenant isolation
- **Deploy**: Docker Compose + Kubernetes + Traefik

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Git
- (Optional) OpenAI API key

### Development
```bash
# 1. Clone
git clone <repo-url> ai-destination-os
cd ai-destination-os

# 2. Configure
cp .env.example .env
# Edit .env and add OPENAI_API_KEY for AI features

# 3. Launch
docker-compose up --build

# 4. Access
# Frontend: http://localhost:3000
# API: http://localhost:8000
# API Docs: http://localhost:8000/docs
```

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
| Chat | `/api/v1/chat/` |
| RAG | `/api/v1/rag/index`, `/api/v1/rag/search` |
| Content | `/api/v1/content/import/csv`, `/api/v1/content/import/json` |
| Context | `/api/v1/context/weather`, `/api/v1/context/events` |
| Analytics | `/api/v1/analytics/track`, `/api/v1/analytics/dashboard/overview` |
| Bookings | `/api/v1/bookings/`, `/api/v1/bookings/{id}/consent` |
| CV/AR | `/api/v1/cv/identify`, `/api/v1/cv/ar/poi/{id}` |

## Testing

### Backend (78 tests)
```bash
cd backend
pytest tests/ -v --cov=app
```

### Flutter (70 tests)
```bash
cd mobile
flutter test --coverage
```

## Deployment

### Production (Docker Compose + Traefik)
```bash
cp .env.production.example .env.production
# Fill: DB_PASSWORD, SECRET_KEY, DOMAIN, OPENAI_API_KEY
docker-compose -f docker-compose.prod.yml up -d
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
├── backend/          # FastAPI application
│   ├── app/
│   │   ├── main.py
│   │   ├── models.py
│   │   ├── schemas.py
│   │   ├── api/v1/endpoints/
│   │   ├── services/
│   │   └── core/
│   └── tests/        # 78 tests
├── frontend/         # Next.js application
│   ├── src/
│   │   ├── app/
│   │   ├── components/
│   │   └── lib/
│   └── package.json
├── mobile/           # Flutter application
│   ├── lib/
│   │   ├── screens/
│   │   ├── widgets/
│   │   ├── providers/
│   │   └── services/
│   └── test/         # 70 tests
├── deploy/k8s/       # Kubernetes manifests
└── docker-compose.yml
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
