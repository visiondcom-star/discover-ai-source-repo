"""RAG (Retrieval Augmented Generation) service with pgvector."""
import json
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, and_
from app.models import POI, Tenant
from app.config import get_settings

settings = get_settings()


class RAGService:
    def __init__(self, db: AsyncSession, tenant: Tenant):
        self.db = db
        self.tenant = tenant

    async def index_pois(self) -> Dict[str, Any]:
        """Index all POIs for this tenant into vector store."""
        if not settings.OPENAI_API_KEY:
            return {"indexed": 0, "error": "OpenAI API key not configured"}

        try:
            import openai
            client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)

            result = await self.db.execute(
                select(POI).where(
                    and_(POI.tenant_id == self.tenant.id, POI.is_active == True)
                )
            )
            pois = result.scalars().all()

            indexed = 0
            for poi in pois:
                content = f"{poi.name}. {poi.description or ''}. Catégorie: {poi.category}. Ville: {poi.city}. Tags: {', '.join(poi.tags or [])}"

                response = client.embeddings.create(
                    model=settings.EMBEDDING_MODEL,
                    input=content,
                )
                embedding = response.data[0].embedding

                poi.embedding = json.dumps(embedding)
                indexed += 1

            await self.db.commit()
            return {"indexed": indexed, "tenant": self.tenant.slug}

        except Exception as e:
            return {"indexed": 0, "error": str(e)}

    async def search(self, query: str, top_k: int = 5) -> List[Dict[str, Any]]:
        """Semantic search over POIs using vector similarity."""
        if not settings.OPENAI_API_KEY:
            # Fallback to text search
            return await self._text_search(query, top_k)

        try:
            import openai
            client = openai.OpenAI(api_key=settings.OPENAI_API_KEY)

            response = client.embeddings.create(
                model=settings.EMBEDDING_MODEL,
                input=query,
            )
            query_embedding = response.data[0].embedding

            # Get all POIs with embeddings for this tenant
            result = await self.db.execute(
                select(POI).where(
                    and_(
                        POI.tenant_id == self.tenant.id,
                        POI.is_active == True,
                        POI.embedding != None,
                    )
                )
            )
            pois = result.scalars().all()

            # Calculate cosine similarity
            import numpy as np
            query_vec = np.array(query_embedding)

            scored = []
            for poi in pois:
                try:
                    poi_vec = np.array(json.loads(poi.embedding))
                    similarity = np.dot(query_vec, poi_vec) / (np.linalg.norm(query_vec) * np.linalg.norm(poi_vec))
                    scored.append((similarity, poi))
                except:
                    continue

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

        except Exception as e:
            return await self._text_search(query, top_k)

    async def _text_search(self, query: str, top_k: int = 5) -> List[Dict[str, Any]]:
        """Fallback text-based search."""
        result = await self.db.execute(
            select(POI).where(
                and_(
                    POI.tenant_id == self.tenant.id,
                    POI.is_active == True,
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
