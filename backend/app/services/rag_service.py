"""RAG (Retrieval Augmented Generation) service with pgvector.

Embeddings go through the configured LLM provider (Prinzip 7 im CLAUDE.md) --
this module never talks to a specific embedding API directly. One embedding
per POI, stored in the pois.embedding vector column (1536 dims, matching
OpenAI's text-embedding-3-small) and searched server-side with pgvector's
cosine-distance operator (<=>) backed by an HNSW index.

Explicit guard: if the configured provider is the deterministic MockProvider
(no LLM_PROVIDER=openai + OPENAI_API_KEY configured), indexing and vector
search are refused rather than silently writing/matching fake vectors --
callers fall back to keyword search instead.
"""
import logging
from typing import List, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models import POI, Tenant
from app.services.llm_providers.factory import get_llm_provider
from app.services.llm_providers.mock_provider import MockProvider

logger = logging.getLogger(__name__)

NO_PROVIDER_ERROR = (
    "No real embedding provider configured "
    "(set LLM_PROVIDER=openai and OPENAI_API_KEY)"
)


class RAGService:
    def __init__(self, db: AsyncSession, tenant: Tenant):
        self.db = db
        self.tenant = tenant
        self.provider = get_llm_provider()

    @staticmethod
    def _poi_to_text(poi: POI) -> str:
        """Canonical text representation used both at index and (implicitly) query time."""
        categories = ", ".join(poi.categories or [])
        tags = ", ".join(poi.tags or [])
        description = poi.description or ""
        return f"{poi.name}. {description}. Categories: {categories}. Ville: {poi.city}. Tags: {tags}"

    async def index_pois(self) -> Dict[str, Any]:
        """Embed every active POI of this tenant and store vectors in Postgres."""
        if isinstance(self.provider, MockProvider):
            return {"indexed": 0, "error": NO_PROVIDER_ERROR}

        try:
            result = await self.db.execute(
                select(POI).where(
                    and_(POI.tenant_id == self.tenant.id, POI.is_active == True)  # noqa: E712
                )
            )
            pois = result.scalars().all()
            if not pois:
                return {"indexed": 0, "tenant": self.tenant.slug}

            indexed = 0
            for poi in pois:
                poi.embedding = await self.provider.embed(self._poi_to_text(poi))
                indexed += 1

            await self.db.commit()
            return {"indexed": indexed, "tenant": self.tenant.slug}

        except Exception as e:
            await self.db.rollback()
            return {"indexed": 0, "error": str(e)}

    async def search(self, query: str, top_k: int = 5) -> List[Dict[str, Any]]:
        """Semantic search over POIs using pgvector cosine distance (SQL-side KNN,
        HNSW-indexed) -- never loads the whole table into memory."""
        if isinstance(self.provider, MockProvider):
            return await self._text_search(query, top_k)

        try:
            query_vec = await self.provider.embed(query)

            result = await self.db.execute(
                select(POI)
                .where(
                    and_(
                        POI.tenant_id == self.tenant.id,
                        POI.is_active == True,  # noqa: E712
                        POI.embedding.isnot(None),
                    )
                )
                .order_by(POI.embedding.cosine_distance(query_vec))
                .limit(top_k)
            )
            pois = result.scalars().all()

            results = []
            for poi in pois:
                distance = await self.db.scalar(
                    select(POI.embedding.cosine_distance(query_vec)).where(POI.id == poi.id)
                )
                results.append({
                    "poi_id": str(poi.id),
                    "name": poi.name,
                    "score": float(1 - distance) if distance is not None else None,
                    "description": poi.description,
                    "city": poi.city,
                    "categories": poi.categories,
                })

            return results

        except Exception:
            logger.warning(
                "RAG vector search failed for tenant %s, falling back to keyword search",
                self.tenant.slug,
                exc_info=True,
            )
            return await self._text_search(query, top_k)

    async def _text_search(self, query: str, top_k: int = 5) -> List[Dict[str, Any]]:
        """Fallback text-based search."""
        result = await self.db.execute(
            select(POI).where(
                and_(
                    POI.tenant_id == self.tenant.id,
                    POI.is_active == True,  # noqa: E712
                )
            )
        )
        pois = result.scalars().all()

        query_lower = query.lower()
        scored = []
        for poi in pois:
            score = 0
            categories = " ".join(poi.categories or [])
            text_content = f"{poi.name} {poi.description or ''} {poi.city} {categories}"
            text_lower = text_content.lower()

            query_words = query_lower.split()
            for word in query_words:
                if word in text_lower:
                    score += 1

            if score > 0:
                scored.append((score, poi))

        scored.sort(reverse=True, key=lambda x: x[0])

        results = []
        for score, poi in scored[:top_k]:
            results.append({
                "poi_id": str(poi.id),
                "name": poi.name,
                "score": float(score),
                "description": poi.description,
                "city": poi.city,
                "categories": poi.categories,
            })

        return results
