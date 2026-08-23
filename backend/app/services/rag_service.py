"""RAG (Retrieval Augmented Generation) service with pgvector.

One embedding per POI (1536 dims, text-embedding-3-small), stored in the
pois.embedding vector column and searched server-side with pgvector's
cosine-distance operator (<=>) backed by an HNSW index.
"""
from typing import List, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.models import POI, Tenant
from app.config import get_settings

settings = get_settings()

# OpenAI embeddings API accepts up to ~2048 inputs per call; stay conservative.
EMBEDDING_BATCH_SIZE = 100


class RAGService:
    def __init__(self, db: AsyncSession, tenant: Tenant):
        self.db = db
        self.tenant = tenant

    @staticmethod
    def _poi_to_text(poi: POI) -> str:
        """Canonical text representation used both at index and (implicitly) query time."""
        return (
            f"{poi.name}. {poi.description or ''}. "
            f"Catégorie: {poi.category}. Ville: {poi.city}. "
            f"Tags: {', '.join(poi.tags or [])}"
        )

    async def index_pois(self) -> Dict[str, Any]:
        """Embed every active POI of this tenant and store vectors in Postgres."""
        if not settings.OPENAI_API_KEY:
            return {"indexed": 0, "error": "OpenAI API key not configured"}

        try:
            import openai
            client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)

            result = await self.db.execute(
                select(POI).where(
                    and_(POI.tenant_id == self.tenant.id, POI.is_active == True)  # noqa: E712
                )
            )
            pois = result.scalars().all()
            if not pois:
                return {"indexed": 0, "tenant": self.tenant.slug}

            # Batch: one API call per EMBEDDING_BATCH_SIZE POIs instead of one call each.
            indexed = 0
            for start in range(0, len(pois), EMBEDDING_BATCH_SIZE):
                chunk = pois[start:start + EMBEDDING_BATCH_SIZE]
                response = client.embeddings.create(
                    model=settings.EMBEDDING_MODEL,
                    input=[self._poi_to_text(poi) for poi in chunk],
                )
                # API returns embeddings ordered by input index.
                for poi, item in zip(chunk, sorted(response.data, key=lambda d: d.index)):
                    poi.embedding = item.embedding
                    indexed += 1

            await self.db.commit()
            return {"indexed": indexed, "tenant": self.tenant.slug}

        except Exception as e:
            await self.db.rollback()
            return {"indexed": 0, "error": str(e)}

    async def search(self, query: str, top_k: int = 5) -> List[Dict[str, Any]]:
        """Semantic search over POIs using pgvector cosine distance (SQL-side KNN,
        HNSW-indexed) — never loads the whole table into memory."""
        if not settings.OPENAI_API_KEY:
            return await self._text_search(query, top_k)

        try:
            import openai
            client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)

            response = client.embeddings.create(
                model=settings.EMBEDDING_MODEL,
                input=query,
            )
            query_vec = response.data[0].embedding

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
                # Recompute exact cosine similarity for the returned rows only.
                distance = await self.db.scalar(
                    select(POI.embedding.cosine_distance(query_vec)).where(POI.id == poi.id)
                )
                results.append({
                    "poi_id": str(poi.id),
                    "name": poi.name,
                    "score": float(1 - distance) if distance is not None else None,
                    "description": poi.description,
                    "city": poi.city,
                    "category": poi.category,
                })

            return results

        except Exception:
            # Any failure (API down, dimension mismatch...) degrades gracefully.
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
            text_content = f"{poi.name} {poi.description or ''} {poi.city} {poi.category}"
            text_lower = text_content.lower()

            # Simple word matching
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
                "category": poi.category,
            })

        return results
