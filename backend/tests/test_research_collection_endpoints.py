"""Tests HTTP des endpoints POST .../research/collection/run et
GET .../research/collection/jobs/{job_id} — isolation tenant, verrou de
concurrence, rate-limit, sur le modèle de test_research_documents.py /
test_research_document_upload.py.

`run_collection_job` est monkeypatché en simulacre : ces tests valident le
contrat HTTP (statuts, 404/409/429, isolation), pas la collecte elle-même
(déjà couverte par test_research_collection.py). Sans ça, BackgroundTasks
exécuterait un vrai job réseau vers Wikimedia à chaque requête de test — et
le job resterait indéfiniment "pending", ce qui fausserait aussi le test du
rate-limit en laissant le verrou de concurrence se déclencher à sa place.
"""
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select, text

from app.api.v1.endpoints.tenants import _run_collection_then_pipeline
from app.models import ResearchCollectionJob, ResearchJob


def _run_url(tenant_id):
    return f"/api/v1/tenants/{tenant_id}/research/collection/run"


def _job_url(tenant_id, job_id):
    return f"/api/v1/tenants/{tenant_id}/research/collection/jobs/{job_id}"


def _research_run_url(tenant_id):
    return f"/api/v1/tenants/{tenant_id}/research/run"


@pytest.fixture(autouse=True)
def _noop_collection_runner(monkeypatch):
    """Simule une collecte instantanée : marque le job "done" sans toucher
    au réseau, pour que le verrou de concurrence (pending/processing) ne
    reste pas bloqué indéfiniment et n'interfère pas avec le test du
    rate-limit, qui doit isoler ce seul garde-fou."""

    async def _fake_done(job_id):
        from app.database import AsyncSessionLocal

        async with AsyncSessionLocal() as session:
            job = await session.get(ResearchCollectionJob, job_id)
            if job:
                job.status = "done"
                job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
                await session.commit()

    monkeypatch.setattr("app.api.v1.endpoints.tenants.run_collection_job", _fake_done)


@pytest.mark.asyncio
async def test_start_collection_success_202(client, admin_headers, test_tenant):
    response = await client.post(
        _run_url(test_tenant.id),
        headers=admin_headers,
        json={"territory": "Tlemcen", "languages": ["fr"]},
    )
    assert response.status_code == 202
    data = response.json()
    assert data["tenant_id"] == str(test_tenant.id)
    assert data["status"] == "pending"
    assert data["documents_fetched"] == 0


@pytest.mark.asyncio
async def test_start_collection_unknown_tenant_404(client, admin_headers):
    response = await client.post(
        _run_url("00000000-0000-0000-0000-000000000000"),
        headers=admin_headers,
        json={},
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_start_collection_is_tenant_isolated(client, other_admin_headers, test_tenant):
    # Isolation des routes /{tenant_id}/... : un admin d'un autre tenant reçoit 404.
    response = await client.post(
        _run_url(test_tenant.id),
        headers=other_admin_headers,
        json={},
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_start_collection_rejects_when_job_already_active(
    client, admin_headers, db_session, test_tenant
):
    active = ResearchCollectionJob(tenant_id=test_tenant.id, status="processing")
    db_session.add(active)
    await db_session.commit()

    response = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert response.status_code == 409


@pytest.mark.asyncio
async def test_start_collection_rate_limited_after_recent_job(
    client, admin_headers, test_tenant
):
    first = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert first.status_code == 202

    second = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert second.status_code == 429


@pytest.mark.asyncio
async def test_get_collection_job_status_200(client, admin_headers, db_session, test_tenant):
    job = ResearchCollectionJob(
        tenant_id=test_tenant.id,
        status="done",
        documents_fetched=2,
        documents_new=1,
        documents_duplicate=1,
    )
    db_session.add(job)
    await db_session.commit()
    await db_session.refresh(job)

    response = await client.get(_job_url(test_tenant.id, job.id), headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "done"
    assert data["documents_fetched"] == 2


@pytest.mark.asyncio
async def test_get_collection_job_not_found_404(client, admin_headers, test_tenant):
    response = await client.get(
        _job_url(test_tenant.id, uuid.uuid4()), headers=admin_headers
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_get_collection_job_is_tenant_isolated(
    client, other_admin_headers, db_session, test_tenant
):
    job = ResearchCollectionJob(tenant_id=test_tenant.id, status="pending")
    db_session.add(job)
    await db_session.commit()
    await db_session.refresh(job)

    response = await client.get(_job_url(test_tenant.id, job.id), headers=other_admin_headers)
    assert response.status_code == 404


# ===== run_pipeline (opt-in) + research_job_id (suivi) =====


@pytest.mark.asyncio
async def test_start_collection_default_does_not_chain_pipeline(client, admin_headers, test_tenant):
    response = await client.post(_run_url(test_tenant.id), headers=admin_headers, json={})
    assert response.status_code == 202
    data = response.json()
    assert data["run_pipeline"] is False
    assert data["research_job_id"] is None


@pytest.mark.asyncio
async def test_start_collection_with_run_pipeline_flag(client, admin_headers, test_tenant):
    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
    )
    assert response.status_code == 202
    data = response.json()
    assert data["run_pipeline"] is True
    assert data["research_job_id"] is None


@pytest.mark.asyncio
async def test_start_collection_rejects_non_boolean_run_pipeline(client, admin_headers, test_tenant):
    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": "peut-etre"}
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_get_collection_job_exposes_chained_research_job_id(
    client, admin_headers, db_session, test_tenant
):
    """Suivi après coup : le research_job_id écrit dans params par la collecte
    ressort sur le GET, ainsi que le run_pipeline demandé au POST."""
    research_job_id = uuid.uuid4()
    job = ResearchCollectionJob(
        tenant_id=test_tenant.id,
        status="done",
        documents_fetched=1,
        documents_new=1,
        params={"run_pipeline": True, "research_job_id": str(research_job_id)},
    )
    db_session.add(job)
    await db_session.commit()
    await db_session.refresh(job)

    response = await client.get(_job_url(test_tenant.id, job.id), headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["run_pipeline"] is True
    assert data["research_job_id"] == str(research_job_id)


@pytest.mark.asyncio
async def test_get_collection_job_without_run_pipeline_is_false(
    client, admin_headers, db_session, test_tenant
):
    """Une clé absente dans params se lit False : la réponse reste un booléen,
    jamais null (le POST n'écrit le drapeau que s'il est demandé)."""
    job = ResearchCollectionJob(
        tenant_id=test_tenant.id,
        status="done",
        params={"territory": "Tizi Ouzou"},
    )
    db_session.add(job)
    await db_session.commit()
    await db_session.refresh(job)

    response = await client.get(_job_url(test_tenant.id, job.id), headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["run_pipeline"] is False
    assert data["research_job_id"] is None


# ===== Chaînage collecte -> pipeline (_run_collection_then_pipeline) =====


def _fake_collection(status, new):
    """Runner de collecte simulé : fixe statut et compteur de documents sans
    toucher au réseau, pour piloter la décision de chaînage."""

    async def _fake(job_id):
        from app.database import AsyncSessionLocal

        async with AsyncSessionLocal() as session:
            job = await session.get(ResearchCollectionJob, job_id)
            job.status = status
            job.documents_new = new
            job.finished_at = datetime.now(timezone.utc).replace(tzinfo=None)
            await session.commit()

    return _fake


@pytest.fixture
def pipeline_calls(monkeypatch):
    """Capture les ids passés à _run_research_pipeline, sans exécuter le LLM."""
    calls = []

    async def _fake_pipeline(research_job_id):
        calls.append(research_job_id)

    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants._run_research_pipeline", _fake_pipeline
    )
    return calls


def _all_collection_jobs(tenant_id):
    """Liste les jobs de collecte du tenant via une session dédiée.

    Utilisée après un crash de tâche de fond, où la session du test n'a pas
    pu être réutilisée pour lire l'état écrit par la tâche.
    """
    from app.database import AsyncSessionLocal

    async def _load():
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                select(ResearchCollectionJob).where(
                    ResearchCollectionJob.tenant_id == tenant_id
                )
            )
            return list(result.scalars().all())

    return _load()


@pytest.mark.asyncio
async def test_chain_runs_pipeline_when_new_documents(
    client, admin_headers, test_tenant, monkeypatch, pipeline_calls
):
    """Collecte done + documents nouveaux + aucun ResearchJob actif => le
    pipeline est enchaîné, et le job créé est un vrai ResearchJob `collection`
    (valeur que le miroir mobile sait désérialiser)."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job", _fake_collection("done", 2)
    )
    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
    )
    assert response.status_code == 202

    job = (
        await client.get(
            _job_url(test_tenant.id, response.json()["id"]), headers=admin_headers
        )
    ).json()
    assert job["research_job_id"] is not None
    assert pipeline_calls and str(pipeline_calls[0]) == job["research_job_id"]

    research = await client.get(
        f"/api/v1/tenants/{test_tenant.id}/research/jobs/{job['research_job_id']}",
        headers=admin_headers,
    )
    assert research.status_code == 200
    assert research.json()["trigger_type"] == "collection"


@pytest.mark.asyncio
async def test_chain_skipped_when_nothing_new(
    client, admin_headers, test_tenant, monkeypatch, pipeline_calls
):
    """0 document nouveau => pas de ResearchJob : inutile de payer un LLM."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job", _fake_collection("done", 0)
    )
    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
    )
    job = (
        await client.get(
            _job_url(test_tenant.id, response.json()["id"]), headers=admin_headers
        )
    ).json()
    assert job["research_job_id"] is None
    assert pipeline_calls == []


@pytest.mark.asyncio
async def test_chain_skipped_when_collection_failed(
    client, admin_headers, test_tenant, monkeypatch, pipeline_calls
):
    """Une collecte failed ne déclenche rien, même si elle a produit des
    documents : c'est le statut `done` qui autorise le chaînage, pas le seul
    compteur."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job",
        _fake_collection("failed", 3),
    )
    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
    )
    job = (
        await client.get(
            _job_url(test_tenant.id, response.json()["id"]), headers=admin_headers
        )
    ).json()
    assert job["status"] == "failed"
    assert job["research_job_id"] is None
    assert pipeline_calls == []


@pytest.mark.asyncio
async def test_no_chain_when_another_research_job_is_active(
    client, admin_headers, db_session, test_tenant, monkeypatch, pipeline_calls
):
    """Le pipeline consomme tous les documents `raw` du tenant : s'il tourne
    déjà, on ne lance pas un second run concurrent."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job", _fake_collection("done", 3)
    )

    active = ResearchJob(
        tenant_id=test_tenant.id, trigger_type="manual_refresh", status="processing"
    )
    db_session.add(active)
    await db_session.commit()

    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
    )
    polled = await client.get(
        _job_url(test_tenant.id, response.json()["id"]), headers=admin_headers
    )
    assert polled.json()["research_job_id"] is None
    assert pipeline_calls == []

    result = await db_session.execute(
        select(ResearchJob).where(ResearchJob.tenant_id == test_tenant.id)
    )
    # Seul le job préexistant : aucun second ResearchJob n'a été créé.
    assert [j.id for j in result.scalars().all()] == [active.id]


@pytest.mark.asyncio
async def test_without_run_pipeline_the_chain_helper_is_not_used(
    client, admin_headers, db_session, test_tenant, monkeypatch, pipeline_calls
):
    """Sans le drapeau, le POST lance la collecte seule (branche `else` du
    runner) : 5 documents trouvés ne suffisent pas à déclencher le pipeline."""
    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job", _fake_collection("done", 5)
    )

    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={}
    )
    assert response.status_code == 202
    assert pipeline_calls == []

    result = await db_session.execute(
        select(ResearchJob).where(ResearchJob.tenant_id == test_tenant.id)
    )
    assert result.scalars().all() == []


@pytest.mark.asyncio
async def test_pipeline_failure_does_not_downgrade_collection(
    client, admin_headers, test_tenant, monkeypatch
):
    """Échec métier du pipeline (le LLM le marque `failed` lui-même) : la
    collecte reste `done` et garde son research_job_id, donc l'écran peut
    suivre le job de recherche sans croire que la collecte a échoué."""

    async def _failing_pipeline(research_job_id):
        from app.database import AsyncSessionLocal

        async with AsyncSessionLocal() as session:
            research_job = await session.get(ResearchJob, research_job_id)
            research_job.status = "failed"
            research_job.error_message = "quota_exceeded: plus de crédit"
            await session.commit()

    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job", _fake_collection("done", 1)
    )
    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants._run_research_pipeline", _failing_pipeline
    )

    response = await client.post(
        _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
    )
    assert response.status_code == 202

    polled = await client.get(
        _job_url(test_tenant.id, response.json()["id"]), headers=admin_headers
    )
    data = polled.json()
    assert data["status"] == "done"
    assert data["documents_new"] == 1
    assert data["research_job_id"] is not None

    # Le job de recherche existe bien et expose son échec au polling.
    research = await client.get(
        f"/api/v1/tenants/{test_tenant.id}/research/jobs/{data['research_job_id']}",
        headers=admin_headers,
    )
    assert research.status_code == 200
    assert research.json()["status"] == "failed"
    assert research.json()["trigger_type"] == "collection"


@pytest.mark.asyncio
async def test_unexpected_pipeline_crash_leaves_collection_done(
    client, admin_headers, test_tenant, monkeypatch
):
    """Si _run_research_pipeline lève malgré tout, l'exception remonte dans la
    tâche de fond (Starlette la propage en test ; en production le 202 est
    déjà envoyé). Ce qui compte : la ligne de collecte n'est pas dégradée."""

    async def _boom(research_job_id):
        raise RuntimeError("LLM indisponible")

    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants.run_collection_job",
        _fake_collection("done", 1),
    )
    monkeypatch.setattr("app.api.v1.endpoints.tenants._run_research_pipeline", _boom)

    collection_job_id = None
    with pytest.raises(RuntimeError):
        response = await client.post(
            _run_url(test_tenant.id), headers=admin_headers, json={"run_pipeline": True}
        )
        collection_job_id = uuid.UUID(response.json()["id"])

    # Le job a bien été créé avant le crash : on le retrouve par son tenant.
    result = await _all_collection_jobs(test_tenant.id)
    assert len(result) == 1
    assert result[0].status == "done"
    assert result[0].documents_new == 1
    assert result[0].research_job_id is not None


@pytest.mark.asyncio
async def test_chain_helper_is_a_noop_on_unknown_job(db_session):
    """Job de collecte introuvable : le helper rend la main sans lever
    (même convention que run_collection_job)."""
    await _run_collection_then_pipeline(uuid.uuid4())


@pytest.mark.asyncio
async def test_collection_job_does_not_consume_manual_refresh_cooldown(
    client, admin_headers, test_tenant, db_session, pipeline_calls
):
    """Un job `collection` ne doit pas consommer le cooldown manual_refresh.

    Le rate-limit de /research/run filtre sur `trigger_type ==
    "manual_refresh"` : sinon, enchaîner une collecte sur le pipeline
    priverait l'admin de son actualisation manuelle du mois, alors que
    l'opt-in a été déclenché par la plateforme et non par lui.

    Le contrôle négatif (un manual_refresh bloque bien le suivant) est
    indispensable : sans lui, ce test passerait aussi si le rate-limit
    disparaissait entièrement.
    """
    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id, trigger_type="collection", status="done"
        )
    )
    await db_session.commit()

    response = await client.post(
        _research_run_url(test_tenant.id),
        headers=admin_headers,
        json={"trigger_type": "manual_refresh"},
    )
    assert response.status_code == 202, response.text
    assert response.json()["trigger_type"] == "manual_refresh"

    # Le job manual_refresh créé ci-dessus doit passer à `done` avant le
    # second POST : `pipeline_calls` neutralise _run_research_pipeline, donc
    # il reste `pending` et déclencherait le garde-fou de concurrence (409)
    # au lieu du cooldown (429) — on veut tester le cooldown, rien d'autre.
    await db_session.execute(
        text(
            "UPDATE research_jobs SET status = 'done' "
            "WHERE tenant_id = :tid AND trigger_type = 'manual_refresh'"
        ),
        {"tid": str(test_tenant.id)},
    )
    await db_session.commit()

    # Contrôle négatif : le cooldown manuel, lui, s'applique toujours.
    blocked = await client.post(
        _research_run_url(test_tenant.id),
        headers=admin_headers,
        json={"trigger_type": "manual_refresh"},
    )
    assert blocked.status_code == 429, (
        "le cooldown manual_refresh doit rester actif après le job "
        f"collection (reçu {blocked.status_code})"
    )


# ===== Garde-fou de concurrence sur /research/run =====


@pytest.mark.asyncio
@pytest.mark.parametrize("active_status", ["pending", "processing"])
@pytest.mark.parametrize(
    "blocking_trigger", ["collection", "scheduled", "admin_replay"]
)
async def test_run_research_conflicts_when_job_already_active(
    client,
    admin_headers,
    test_tenant,
    db_session,
    pipeline_calls,
    active_status,
    blocking_trigger,
):
    """Un run est refusé (409) si un autre job du tenant est pending/processing.

    Symétrique du garde-fou de la collecte : le pipeline lit TOUS les documents
    `raw` du tenant, donc deux runs concurrents consommeraient les mêmes
    documents (le second ne verrait que ce que le premier a laissé).

    Le `trigger_type` du job bloquant est paramétré parce que le garde-fou doit
    être agnostique : `collection` est le nouveau cas de cette branche, mais un
    `scheduled` ou un `admin_replay` en vol doit bloquer tout autant.

    On demande `admin_replay` (et non `manual_refresh`) pour ne pas traverser le
    rate-limit mensuel : le seul garde-fou en jeu reste alors la concurrence,
    et un 202 inattendu ne pourra pas être attribué au cooldown.
    """
    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id,
            trigger_type=blocking_trigger,
            status=active_status,
        )
    )
    await db_session.commit()

    blocked = await client.post(
        _research_run_url(test_tenant.id),
        headers=admin_headers,
        json={"trigger_type": "admin_replay"},
    )
    assert blocked.status_code == 409, (
        f"un job {blocking_trigger}/{active_status} doit bloquer un nouveau run "
        f"(reçu {blocked.status_code})"
    )
    assert pipeline_calls == [], "aucun pipeline ne doit démarrer sur un refus"


@pytest.mark.asyncio
@pytest.mark.parametrize("finished_status", ["done", "failed"])
async def test_run_research_accepted_when_previous_job_finished(
    client,
    admin_headers,
    test_tenant,
    db_session,
    pipeline_calls,
    finished_status,
):
    """Un job terminal (`done` ou `failed`) ne bloque pas le run suivant.

    Contrôle négatif du garde-fou : sans lui, le test passerait aussi si le
    409 se déclenchait pour n'importe quel job existant — et le tenant serait
    bloqué indéfiniment après son premier run.

    `failed` est inclus parce que c'est un statut courant : un run en erreur
    technique ne doit pas condamner le tenant à ne plus jamais relancer.
    """
    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id, trigger_type="scheduled", status=finished_status
        )
    )
    await db_session.commit()

    response = await client.post(
        _research_run_url(test_tenant.id),
        headers=admin_headers,
        json={"trigger_type": "admin_replay"},
    )
    assert response.status_code == 202, response.text
    # admin_replay n'est pas concerné par le cooldown : le 202 prouve bien que
    # seul le garde-fou de concurrence était en jeu ici.
    assert len(pipeline_calls) == 1


@pytest.mark.asyncio
async def test_run_research_conflict_is_scoped_to_the_tenant(
    client,
    admin_headers,
    other_admin_headers,
    db_session,
    test_tenant,
    other_tenant,
    pipeline_calls,
):
    """Un job actif chez test_tenant ne bloque pas le run de other_tenant.

    Sans le filtre sur `tenant_id`, un tenant très actif sature la file de
    tous les autres : le garde-fou doit rester strictement cloisonné.
    """
    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id, trigger_type="collection", status="processing"
        )
    )
    await db_session.commit()

    # Le tenant bloqué refuse bien son propre run...
    blocked = await client.post(
        _research_run_url(test_tenant.id),
        headers=admin_headers,
        json={"trigger_type": "admin_replay"},
    )
    assert blocked.status_code == 409, blocked.text

    # ...mais l'autre tenant passe.
    allowed = await client.post(
        _research_run_url(other_tenant.id),
        headers=other_admin_headers,
        json={"trigger_type": "admin_replay"},
    )
    assert allowed.status_code == 202, allowed.text
    assert len(pipeline_calls) == 1, "seul le tenant libre doit lancer un pipeline"
