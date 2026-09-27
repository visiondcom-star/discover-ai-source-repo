"""Tests du pipeline réel `_run_research_pipeline` (backend/app/api/v1/endpoints/tenants.py).

Couvre :
1. extraction réussie → catégories créées avec le bon statut (active si
   mapping_confidence >= 0.90 ET category_confidence >= 0.85 ET parent
   résolu, sinon proposed) et compteurs du job exacts ;
2. dédup par slug existant → document marqué processed SANS doublon créé
   (la UniqueConstraint n'est jamais testée en échec : la vérification
   applicative l'empêche en amont) ;
3. document sans candidat exploitable → reste status="raw" (retentable) ;
4. QuotaExceededError pendant l'extraction → job failed avec error_message
   préfixé "quota_exceeded:", et ce job ne compte PAS dans le rate-limit
   manual_refresh (second run accepté, pas de 429) ;
5. erreur technique → job failed SANS le préfixe, et celle-là compte bien
   dans le cooldown (second run → 429).
"""
import json
import uuid

import pytest
from slugify import slugify

import app.services.research_service as research_service_module
from app.models import DestinationResearchDocument, TenantCategory
from app.services.llm_providers.base import CompletionResult, TokenUsage
from app.services.tenant_ai_quota_service import QuotaExceededError

pytestmark = pytest.mark.asyncio

API = "/api/v1/tenants"
RUN_MANUAL = {"trigger_type": "manual_refresh"}


class FakeProvider:
    """Provider LLM factice : renvoie le JSON de réponse pré-construit."""

    def __init__(self, reply):
        self.reply = reply
        self.name = "openai"
        self.configured_model = "gpt-4o"

    async def complete(self, messages, temperature=0.3, max_tokens=2000):
        return CompletionResult(
            text=self.reply,
            model="gpt-4o",
            usage=TokenUsage(prompt_tokens=10, completion_tokens=5),
        )


def _patch_llm(monkeypatch, reply=None, error=None):
    """Remplace la résolution provider du tenant (quota + BYOK) par un fake.

    `error` simule la résolution qui échoue : c'est le seul point d'entrée
    hors try dans ResearchService.extract_categories, donc QuotaExceededError
    ET les erreurs techniques de résolution y remontent telles quelles.
    """

    async def fake_resolver(db, tenant_id, feature):
        if error is not None:
            raise error
        return FakeProvider(reply=reply)

    monkeypatch.setattr(
        research_service_module, "get_tenant_llm_provider", fake_resolver
    )


async def _ingest(client, admin_headers, tenant_id, raw_text):
    """Ingeste un document brut (étape Ingestion, déjà couverte ailleurs)."""
    response = await client.post(
        f"{API}/{tenant_id}/research/documents",
        headers=admin_headers,
        json={"source_type": "guide", "raw_text": raw_text, "language": "fr"},
    )
    assert response.status_code == 200, response.text
    return uuid.UUID(response.json()["id"])


async def _run_and_wait(client, admin_headers, tenant_id):
    """Lance un run manual_refresh et renvoie le job une fois terminé.

    Avec ASGITransport, la tâche de fond est terminée quand la réponse du
    POST revient : le poll suivant lit l'état final.
    """
    response = await client.post(
        f"{API}/{tenant_id}/research/run", headers=admin_headers, json=RUN_MANUAL
    )
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    polled = await client.get(
        f"{API}/{tenant_id}/research/jobs/{job_id}", headers=admin_headers
    )
    assert polled.status_code == 200, polled.text
    return polled.json()


def _candidate(label, doc_id, *, parent="history", mapping=0.95, category=0.95):
    return {
        "label": label,
        "description": f"{label} — proposition extraite des documents de recherche.",
        "parent_level1_id": parent,
        "mapping_confidence": mapping,
        "category_confidence": category,
        "suggested_icon": "castle",
        "source_document_ids": [str(doc_id)],
    }


# ------------------------------------------------------------------ 1. succès


async def test_extraction_success_creates_categories_with_right_status(
    monkeypatch, client, admin_headers, test_tenant, db_session
):
    from sqlalchemy import select

    doc_id = await _ingest(
        client,
        admin_headers,
        test_tenant.id,
        "La Casbah d'Alger est un site classé ; les sentiers de montagne et "
        "la gastronomie locale attirent les visiteurs toute l'année.",
    )
    reply = json.dumps(
        [
            # active : mapping 0.95 >= 0.90, category 0.90 >= 0.85, parent résolu
            _candidate("Monuments historiques", doc_id, parent="history",
                       mapping=0.95, category=0.90),
            # proposed : parent Niveau 1 non résolu (None). mapping 0.70
            # < category 0.92 : confidence doit valoir le plus faible (0.70),
            # pas le category_confidence trompeusement élevé.
            _candidate("Randonnée en montagne", doc_id, parent=None,
                       mapping=0.70, category=0.92),
            # proposed : category_confidence 0.80 < 0.85
            _candidate("Gastronomie locale", doc_id, parent="food",
                       mapping=0.95, category=0.80),
        ]
    )
    _patch_llm(monkeypatch, reply=reply)

    job = await _run_and_wait(client, admin_headers, test_tenant.id)

    assert job["status"] == "done"
    assert job["categories_proposed"] == 3
    assert job["categories_auto_published"] == 1
    assert job["categories_pending_review"] == 2
    assert job["error_message"] is None

    rows = (
        await db_session.execute(
            select(TenantCategory).where(TenantCategory.tenant_id == test_tenant.id)
        )
    ).scalars().all()
    by_slug = {row.slug: row for row in rows}
    assert set(by_slug) == {
        "monuments-historiques",
        "randonnee-en-montagne",
        "gastronomie-locale",
    }

    active = by_slug["monuments-historiques"]
    assert active.status == "active"
    assert active.parent_family == "history"
    assert active.confidence == pytest.approx(0.90)
    assert active.research_document_id == doc_id
    assert active.ai_generated is True

    # parent non résolu → proposed, même avec d'excellentes confiances.
    assert by_slug["randonnee-en-montagne"].status == "proposed"
    assert by_slug["randonnee-en-montagne"].parent_family is None
    # confidence = min(mapping, category) : 0.70, pas le 0.92 de category
    # (l'ancienne formule category_confidence seule ferait échouer ce test).
    assert by_slug["randonnee-en-montagne"].confidence == pytest.approx(0.70)
    # category_confidence sous le seuil 0.85 → proposed.
    assert by_slug["gastronomie-locale"].status == "proposed"

    doc = (
        await db_session.execute(
            select(DestinationResearchDocument).where(
                DestinationResearchDocument.id == doc_id
            )
        )
    ).scalar_one()
    assert doc.status == "processed"


# ------------------------------------------------------- 2. dédup par slug


async def test_existing_slug_is_deduped_and_document_still_processed(
    monkeypatch, client, admin_headers, test_tenant, db_session
):
    from sqlalchemy import select

    # Catégorie déjà présente (créée par l'admin, même slug que le candidat).
    created = await client.post(
        f"{API}/categories",
        headers=admin_headers,
        json={"slug": "casbah-medinas", "label": "Casbah Medinas",
              "parent_family": "history"},
    )
    assert created.status_code == 201, created.text

    doc_id = await _ingest(
        client, admin_headers, test_tenant.id,
        "Les médinas et casbahs du territoire abritent un artisanat vivant.",
    )
    reply = json.dumps([_candidate("Casbah Medinas", doc_id, mapping=0.99,
                                   category=0.99)])
    _patch_llm(monkeypatch, reply=reply)

    job = await _run_and_wait(client, admin_headers, test_tenant.id)

    assert job["status"] == "done"
    # Rien créé : le candidat existait déjà, pas de compteur à incrémenter.
    assert job["categories_proposed"] == 0
    assert job["categories_auto_published"] == 0
    assert job["categories_pending_review"] == 0

    # La dédup applicative a empêché l'insert — la UniqueConstraint n'a
    # jamais été en échec (sinon le job serait failed sur IntegrityError).
    rows = (
        await db_session.execute(
            select(TenantCategory).where(
                TenantCategory.tenant_id == test_tenant.id,
                TenantCategory.slug == "casbah-medinas",
            )
        )
    ).scalars().all()
    assert len(rows) == 1
    assert rows[0].status == "active"  # inchangée par le pipeline

    doc = (
        await db_session.execute(
            select(DestinationResearchDocument).where(
                DestinationResearchDocument.id == doc_id
            )
        )
    ).scalar_one()
    assert doc.status == "processed"


# ------------------------------------- 3. sans candidat exploitable → raw


async def test_document_without_usable_candidate_stays_raw_and_retryable(
    monkeypatch, client, admin_headers, test_tenant, db_session
):
    from sqlalchemy import select

    doc_id = await _ingest(
        client, admin_headers, test_tenant.id,
        "Un texte qui n'aboutit à aucune catégorie exploitable.",
    )
    _patch_llm(monkeypatch, reply=json.dumps([]))

    job = await _run_and_wait(client, admin_headers, test_tenant.id)

    # Aucun candidat : pas d'échec, le run aboutit et le doc reste retentable.
    assert job["status"] == "done"
    assert job["categories_proposed"] == 0

    doc = (
        await db_session.execute(
            select(DestinationResearchDocument).where(
                DestinationResearchDocument.id == doc_id
            )
        )
    ).scalar_one()
    assert doc.status == "raw"  # retentable au prochain run

    categories = (
        await db_session.execute(
            select(TenantCategory).where(TenantCategory.tenant_id == test_tenant.id)
        )
    ).scalars().all()
    assert categories == []


# --------------------------- 4. quota dépassé → failed préfixé, pas de 429


async def test_quota_exceeded_fails_job_without_consuming_cooldown(
    monkeypatch, client, admin_headers, test_tenant
):
    await _ingest(
        client, admin_headers, test_tenant.id,
        "Guide touristique complet nécessitant une extraction LLM par le "
        "pipeline de recherche de destination.",
    )
    _patch_llm(
        monkeypatch,
        error=QuotaExceededError(test_tenant.id, monthly_limit=50, current_usage=50),
    )

    first = await _run_and_wait(client, admin_headers, test_tenant.id)

    assert first["status"] == "failed"
    assert first["error_message"].startswith("quota_exceeded:")
    # L'erreur exacte du quota reste lisible dans le message.
    assert str(test_tenant.id) in first["error_message"]

    # Ce job failed-quota est exclu du rate-limit : le second run passe.
    second = await client.post(
        f"{API}/{test_tenant.id}/research/run",
        headers=admin_headers,
        json=RUN_MANUAL,
    )
    assert second.status_code == 202, (
        "un échec par quota ne doit pas consommer le cooldown manual_refresh "
        f"(reçu {second.status_code})"
    )


# ------------------- 5. erreur technique → failed sans préfixe, 429 ensuite


async def test_technical_error_fails_job_and_consumes_cooldown(
    monkeypatch, client, admin_headers, test_tenant
):
    await _ingest(
        client, admin_headers, test_tenant.id,
        "Guide touristique complet nécessitant une extraction LLM par le "
        "pipeline de recherche de destination.",
    )
    _patch_llm(monkeypatch, error=RuntimeError("provider down"))

    first = await _run_and_wait(client, admin_headers, test_tenant.id)

    assert first["status"] == "failed"
    assert first["error_message"] == "provider down"
    assert not first["error_message"].startswith("quota_exceeded:")

    # L'erreur technique compte dans le cooldown → second run bloqué (429).
    second = await client.post(
        f"{API}/{test_tenant.id}/research/run",
        headers=admin_headers,
        json=RUN_MANUAL,
    )
    assert second.status_code == 429, (
        "une erreur technique ordinaire doit rester soumise au cooldown "
        f"(reçu {second.status_code})"
    )

