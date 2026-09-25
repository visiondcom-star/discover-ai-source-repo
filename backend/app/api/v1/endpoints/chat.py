"""AI Chat endpoints."""
from fastapi import APIRouter, Depends, Header, HTTPException  # type: ignore
from sqlalchemy.ext.asyncio import AsyncSession  # type: ignore
from app.database import get_db
from app.schemas import ChatRequest, ChatResponse
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user
from app.services.chat_service import ChatService
from app.services.credential_crypto import CredentialCryptoError
from app.services.tenant_llm_provider import AIFeatureDisabledError, TenantAIError
import structlog

logger = structlog.get_logger(__name__)
router = APIRouter()


@router.post("", response_model=ChatResponse)
@router.post("/", response_model=ChatResponse)
async def chat(
    data: ChatRequest,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user = Depends(get_current_user),
):
    tenant = await get_tenant_from_header(x_tenant_slug)
    # Défense en profondeur : sans cette vérification, un utilisateur authentifié d'un tenant
    # pourrait envoyer le slug d'un autre tenant et consommer sa clé IA (BYOK).
    if current_user.tenant_id != tenant.id:
        raise HTTPException(status_code=403, detail="Accès refusé pour ce tenant.")
    service = ChatService(db, tenant)
    try:
        result = await service.chat(
            user_id=str(current_user.id),
            message=data.message,
            context=data.context,
        )
    except AIFeatureDisabledError:
        raise HTTPException(status_code=403, detail="L'assistant IA n'est pas activé pour ce tenant.")
    except (TenantAIError, CredentialCryptoError) as e:
        logger.error("chat.tenant_ai_config_error", tenant_id=str(tenant.id), error_type=type(e).__name__)
        raise HTTPException(status_code=503, detail="Assistant IA momentanément indisponible.")
    return ChatResponse(**result)
