"""Main API router assembly."""
from fastapi import APIRouter, Depends
from app.api.v1.endpoints import auth, tenants, pois, trips, chat, rag, content, context, analytics, bookings, cv, reviews
from app.dependencies import require_csrf

# The double-submit CSRF guard is a single reusable dependency applied to every
# included data router (FastAPI propagates `dependencies=` from include_router to
# each route). GET/HEAD/OPTIONS and Bearer-authenticated requests bypass it (see
# require_csrf); cookie-authenticated POST/PUT/DELETE must supply X-CSRF-Token.
# NOTE: /auth is deliberately NOT covered router-wide — login/register are CSRF
# bootstrap endpoints (a CSRF token cannot be required before the cookie is
# issued on the first login). The one authenticated mutating auth endpoint,
# POST /auth/logout, opts into the same guard per-endpoint instead.
api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["Authentication"])
api_router.include_router(tenants.router, prefix="/tenants", tags=["Tenants"], dependencies=[Depends(require_csrf)])
api_router.include_router(pois.router, prefix="/pois", tags=["Points of Interest"], dependencies=[Depends(require_csrf)])
api_router.include_router(trips.router, prefix="/trips", tags=["Trip Planning"], dependencies=[Depends(require_csrf)])
api_router.include_router(chat.router, prefix="/chat", tags=["AI Chat"], dependencies=[Depends(require_csrf)])
api_router.include_router(rag.router, prefix="/rag", tags=["RAG / Vector Search"], dependencies=[Depends(require_csrf)])
api_router.include_router(content.router, prefix="/content", tags=["Content Pipeline"], dependencies=[Depends(require_csrf)])
api_router.include_router(context.router, prefix="/context", tags=["Live Context"], dependencies=[Depends(require_csrf)])
api_router.include_router(analytics.router, prefix="/analytics", tags=["Analytics"], dependencies=[Depends(require_csrf)])
api_router.include_router(bookings.router, prefix="/bookings", tags=["Bookings"], dependencies=[Depends(require_csrf)])
api_router.include_router(reviews.router, prefix="/pois", tags=["Reviews"], dependencies=[Depends(require_csrf)])
api_router.include_router(cv.router, prefix="/cv", tags=["Computer Vision & AR"], dependencies=[Depends(require_csrf)])
