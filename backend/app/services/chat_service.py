"""AI Chat service with RAG enhancement and tenant usage tracking."""
import time
from typing import Any, Dict, List, Optional
import structlog
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, text
from app.models import ChatMessage, Tenant
from app.config import get_settings
from app.services.llm_providers.base import TokenUsage
from app.services.llm_providers.errors import classify_provider_error
from app.services.llm_providers.factory import get_llm_provider
from app.services.tenant_ai_quota_service import record_llm_call
from app.services.tenant_llm_provider import get_tenant_llm_provider

logger = structlog.get_logger(__name__)
settings = get_settings()


class ChatService:
    def __init__(self, db: AsyncSession, tenant: Tenant):
        self.db = db
        self.tenant = tenant
        self.system_prompt = self._build_system_prompt()

    def _build_system_prompt(self) -> str:
        return f"""Tu es un guide touristique expert pour {self.tenant.name}.
Tu connais parfaitement l'histoire, la culture, la gastronomie et les sites touristiques.
Tu réponds en {self.tenant.default_language} de manière chaleureuse et informative.
Tu peux suggérer des itinéraires, des restaurants, des activités et répondre aux questions pratiques.
Sois concis mais complet."""

    async def _get_rag_context(self, message: str, limit: int = 3) -> str:
        """
        Find relevant POIs from the database using vector similarity search (RAG).
        """
        if not settings.USE_PGVECTOR:
            return ""

        try:
            provider = get_llm_provider()
            embed_res = await provider.embed(message)
            embedding = embed_res.vector if hasattr(embed_res, "vector") else embed_res

            # `<->` est l'opérateur pgvector pour la distance cosinus.
            query = text("""
                SELECT name, description, city, categories, tags
                FROM pois
                WHERE tenant_id = :tenant_id
                ORDER BY embedding <-> :embedding
                LIMIT :limit
            """)
            result = await self.db.execute(query, {"tenant_id": self.tenant.id, "embedding": str(embedding), "limit": limit})
            pois = result.mappings().all()

            return "\n\n".join([f"POI: {p['name']} ({p['city']}, {', '.join(p['categories'])})\nDescription: {p['description']}\nTags: {', '.join(p['tags'])}" for p in pois])
        except Exception as e:
            # En cas d'erreur d'embedding ou de pgvector, on retombe sur une réponse sans RAG.
            print(f"RAG context retrieval failed: {e}")
            return ""

    async def chat(
        self,
        user_id: str,
        message: str,
        context: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        # Provider du tenant (clé BYOK, modèle choisi), repli sur la config globale s'il n'en a pas.
        # Résolu hors du try et avant le RAG : une erreur de configuration doit remonter
        # à l'endpoint (403/503), pas devenir un message de chat ni coûter un embedding.
        provider = await get_tenant_llm_provider(self.db, self.tenant.id, "chat")
        history = await self._get_history(user_id, limit=10)
        rag_context = await self._get_rag_context(message)

        messages = [{"role": "system", "content": self.system_prompt}]

        if rag_context:
            context_message = f"Voici quelques informations pertinentes pour la question de l'utilisateur. Utilise-les pour formuler ta réponse de manière naturelle. Ne mentionne pas que tu as cherché dans une base de données.\n\n---\n{rag_context}\n---"
            messages.append({"role": "system", "content": context_message})

        for h in history:
            messages.append({"role": h.role, "content": h.content})

        messages.append({"role": "user", "content": message})

        start = time.perf_counter()
        provider_name = getattr(provider, "name", "openai")
        configured_model = getattr(provider, "configured_model", "unknown")
        try:
            result = await provider.complete(messages, temperature=0.7, max_tokens=800)
            latency_ms = int((time.perf_counter() - start) * 1000)
            if hasattr(result, "text"):
                assistant_message = result.text or ""
                served_model = result.model or configured_model
                usage = result.usage or TokenUsage()
            else:
                assistant_message = str(result or "")
                served_model = configured_model
                usage = TokenUsage()
            try:
                await record_llm_call(
                    self.db,
                    self.tenant.id,
                    feature="chat",
                    provider=provider_name,
                    model=served_model,
                    usage=usage,
                    status="success",
                    latency_ms=latency_ms,
                    user_id=user_id,
                )
            except Exception:
                logger.warning("chat.record_llm_call_failed", exc_info=True)
        except Exception as e:
            latency_ms = int((time.perf_counter() - start) * 1000)
            logger.error(
                "chat.completion_failed",
                tenant_id=str(self.tenant.id),
                error_type=type(e).__name__,
            )
            error_code = classify_provider_error(e, provider=provider_name)
            try:
                await record_llm_call(
                    self.db,
                    self.tenant.id,
                    feature="chat",
                    provider=provider_name,
                    model=configured_model,
                    usage=TokenUsage(),
                    status="error",
                    error_code=error_code,
                    latency_ms=latency_ms,
                    user_id=user_id,
                )
            except Exception:
                logger.warning("chat.record_llm_call_failed", exc_info=True)
            assistant_message = (
                "Je suis désolé, je rencontre un problème technique. Réessaie dans un instant."
            )

        suggestions = self._extract_suggestions(assistant_message)

        await self._save_message(user_id, "user", message, context)
        await self._save_message(user_id, "assistant", assistant_message, context)

        return {
            "message": assistant_message,
            "suggestions": suggestions,
            "context": context or {},
        }

    async def _get_history(self, user_id: str, limit: int = 10) -> List[ChatMessage]:
        result = await self.db.execute(
            select(ChatMessage)
            .where(
                and_(
                    ChatMessage.user_id == user_id,
                    ChatMessage.tenant_id == self.tenant.id,
                )
            )
            .order_by(ChatMessage.created_at.desc())
            .limit(limit)
        )
        return list(reversed(result.scalars().all()))

    async def _save_message(
        self,
        user_id: str,
        role: str,
        content: str,
        context: Optional[Dict[str, Any]] = None,
    ) -> None:
        msg = ChatMessage(
            tenant_id=self.tenant.id,
            user_id=user_id,
            role=role,
            content=content,
            context=context or {},
        )
        self.db.add(msg)
        await self.db.commit()

    def _extract_suggestions(self, message: str) -> List[str]:
        """Extract suggested follow-up questions from the response."""
        suggestions = []
        lines = message.split("\n")
        for line in lines:
            if line.strip().startswith("-") or line.strip().startswith("•"):
                sugg = line.strip("- •").strip()
                if len(sugg) > 5 and len(sugg) < 100:
                    suggestions.append(sugg)
        if not suggestions:
            suggestions = ["Explorer les POIs", "Planifier un voyage", "Histoire locale"]
        return suggestions[:3]