"""Main API router assembly."""
from fastapi import APIRouter
from app.api.v1.endpoints import auth, tenants, pois, trips, chat, rag, content, context, analytics, bookings, cv

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["Authentication"])
api_router.include_router(tenants.router, prefix="/tenants", tags=["Tenants"])
api_router.include_router(pois.router, prefix="/pois", tags=["Points of Interest"])
api_router.include_router(trips.router, prefix="/trips", tags=["Trip Planning"])
api_router.include_router(chat.router, prefix="/chat", tags=["AI Chat"])
api_router.include_router(rag.router, prefix="/rag", tags=["RAG / Vector Search"])
api_router.include_router(content.router, prefix="/content", tags=["Content Pipeline"])
api_router.include_router(context.router, prefix="/context", tags=["Live Context"])
api_router.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
api_router.include_router(bookings.router, prefix="/bookings", tags=["Bookings"])
api_router.include_router(cv.router, prefix="/cv", tags=["Computer Vision & AR"])
