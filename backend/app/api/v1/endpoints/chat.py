"""AI Chat endpoints."""
from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.schemas import ChatRequest, ChatResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from app.services.chat_service import ChatService

router = APIRouter()


@router.post("/", response_model=ChatResponse)
async def chat(
    data: ChatRequest,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    service = ChatService(db, tenant)
    result = await service.chat(
        user_id=str(current_user.id),
        message=data.message,
        context=data.context,
    )
    return ChatResponse(**result)
