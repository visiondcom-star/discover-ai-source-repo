"""AI destination-research service — extraction step of the pipeline.

Mirrors the CVService pattern: resolve the active LLM provider via the
factory, ask for strict JSON, parse it, and degrade gracefully (skip, don't
crash) on malformed or invalid candidates rather than failing the whole run.

Scope of this module: extract_categories() only (the Extraction step).
Collection/ingestion of destination_research_documents, deduplication
against existing categories (pgvector), and persistence with the
publication rules (category_confidence >= 0.85, mapping_confidence >= 0.90)
are separate steps, not yet wired into research_service.run_research_job().
"""
import json
import logging
from typing import List

from pydantic import ValidationError

from app.constants import PARENT_FAMILIES
from app.models import DestinationResearchDocument, Tenant
from app.schemas import CategoryCandidate
from app.services.llm_providers.factory import get_llm_provider

logger = logging.getLogger(__name__)

MAX_DOCUMENT_CHARS_PER_PROMPT = 12_000


class ResearchService:
    def __init__(self, tenant: Tenant):
        self.tenant = tenant

    @staticmethod
    def _build_extraction_prompt(
        tenant_name: str,
        documents_text: str,
        existing_labels: List[str],
    ) -> str:
        level1_list = ", ".join(f"'{f}'" for f in PARENT_FAMILIES)
        existing = (
            ", ".join(existing_labels) if existing_labels else "(aucune pour le moment)"
        )
        return (
            f"Tu analyses des documents de recherche touristique pour le territoire "
            f"'{tenant_name}' afin d'en extraire des catégories touristiques de Niveau 2 "
            f"(spécifiques à cette destination), rattachées à une famille de Niveau 1 fixe.\n\n"
            f"Familles de Niveau 1 disponibles (liste fermée, tu ne peux en inventer aucune "
            f"autre) : {level1_list}.\n\n"
            f"Catégories déjà actives pour ce territoire, à ne PAS reproposer à l'identique : "
            f"{existing}.\n\n"
            f"Documents sources :\n---\n{documents_text}\n---\n\n"
            "Retourne un TABLEAU JSON, un objet par catégorie candidate identifiée, "
            "chaque objet contenant exactement ces clés :\n"
            "- 'label': nom court de la catégorie (2 à 80 caractères)\n"
            "- 'description': description en français (10 à 500 caractères)\n"
            "- 'parent_level1_id': une des familles de Niveau 1 listées ci-dessus, ou null "
            "si le rattachement est ambigu\n"
            "- 'mapping_confidence': nombre flottant 0.0-1.0, ta certitude sur le "
            "rattachement Niveau 1 (null/ambigu doit avoir une confiance basse)\n"
            "- 'category_confidence': nombre flottant 0.0-1.0, ta certitude sur la "
            "pertinence de la catégorie elle-même\n"
            "- 'suggested_icon': nom d'icône suggéré (optionnel, peut être null)\n"
            "- 'source_document_ids': liste des IDs de documents (fournis ci-dessous) "
            "qui appuient cette proposition — jamais une liste vide\n\n"
            "N'invente aucune catégorie non appuyée par les documents fournis. "
            "Réponds uniquement avec le tableau JSON, sans texte autour."
        )

    async def extract_categories(
        self,
        documents: List[DestinationResearchDocument],
        existing_labels: List[str],
    ) -> List[CategoryCandidate]:
        if not documents:
            return []

        parts = []
        budget = MAX_DOCUMENT_CHARS_PER_PROMPT
        for doc in documents:
            if budget <= 0:
                break
            excerpt = doc.raw_text[:budget]
            parts.append(f"[document_id: {doc.id}]\n{excerpt}")
            budget -= len(excerpt)
        documents_text = "\n\n".join(parts)

        prompt = self._build_extraction_prompt(
            self.tenant.name, documents_text, existing_labels
        )

        provider = get_llm_provider()
        try:
            result_text = await provider.complete(
                [{"role": "user", "content": prompt}],
                temperature=0.3,
                max_tokens=2000,
            )
            raw_candidates = json.loads(result_text)
            if not isinstance(raw_candidates, list):
                raise ValueError("expected a JSON array")
        except Exception as exc:
            logger.warning("extract_categories: LLM call or JSON parse failed: %s", exc)
            return []

        candidates: List[CategoryCandidate] = []
        for raw in raw_candidates:
            try:
                candidate = CategoryCandidate.model_validate(
                    raw, context={"level1_ids": PARENT_FAMILIES}
                )
            except ValidationError as exc:
                logger.info("extract_categories: candidate rejected: %s", exc)
                continue
            candidates.append(candidate)

        return candidates
