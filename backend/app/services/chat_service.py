"""AI Chat service with RAG enhancement."""
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, text
from app.models import ChatMessage, Tenant
from app.config import get_settings
from app.services.llm_providers.factory import get_llm_provider


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
            embedding = await provider.embed(message)

            # `<->` est l'opérateur pgvector pour la distance cosinus.
            query = text("""
                SELECT name, description, city, category, tags
                FROM pois
                WHERE tenant_id = :tenant_id
                ORDER BY embedding <-> :embedding
                LIMIT :limit
            """)
            result = await self.db.execute(query, {"tenant_id": self.tenant.id, "embedding": str(embedding), "limit": limit})
            pois = result.mappings().all()

            return "\n\n".join([f"POI: {p['name']} ({p['city']}, {p['category']})\nDescription: {p['description']}\nTags: {', '.join(p['tags'])}" for p in pois])
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
        history = await self._get_history(user_id, limit=10)
        rag_context = await self._get_rag_context(message)

        messages = [{"role": "system", "content": self.system_prompt}]

        if rag_context:
            context_message = f"Voici quelques informations pertinentes pour la question de l'utilisateur. Utilise-les pour formuler ta réponse de manière naturelle. Ne mentionne pas que tu as cherché dans une base de données.\n\n---\n{rag_context}\n---"
            messages.append({"role": "system", "content": context_message})

        for h in history:
            messages.append({"role": h.role, "content": h.content})

        messages.append({"role": "user", "content": message})

        provider = get_llm_provider()
        try:
            assistant_message = await provider.complete(messages, temperature=0.7, max_tokens=800)
        except Exception as e:
            assistant_message = f"Je suis désolé, je rencontre un problème technique. ({str(e)})"
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