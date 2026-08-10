"""RAG / Vector Search endpoints."""
from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.schemas import RAGSearchRequest, RAGSearchResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from app.services.rag_service import RAGService

router = APIRouter()


@router.post("/index")
async def index_tenant(
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    service = RAGService(db, tenant)
    result = await service.index_pois()
    return result


@router.post("/search", response_model=RAGSearchResponse)
async def search(
    data: RAGSearchRequest,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    service = RAGService(db, tenant)
    results = await service.search(data.query, data.top_k)
    return RAGSearchResponse(results=results, query=data.query)
