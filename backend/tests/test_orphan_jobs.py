"""Tests du service `fail_orphan_jobs` et de son appel au démarrage.

Un job laissé `pending`/`processing` par un arrêt du serveur n'a plus de tâche
de fond pour le finir : il bloquerait indéfiniment les endpoints (409 sur
/research/run comme sur /research/collection/run). Le lifespan le referme donc.

Le contrat croisé avec le cooldown de manual_refresh est testé ici aussi : un
job `interrupted:` ne doit PAS consommer le cooldown (ce n'est pas la faute de
l'opérateur), alors qu'une erreur technique, elle, doit le consommer.
"""
import pytest
from sqlalchemy import select

from app.models import ResearchCollectionJob, ResearchJob
from app.services.orphan_jobs_service import INTERRUPTED_PREFIX, fail_orphan_jobs


@pytest.mark.asyncio
async def test_fail_orphan_jobs_closes_only_active_jobs(db_session, test_tenant):
    """Seuls `pending`/`processing` sont refermés ; les terminaux sont intacts.

    Un job `done`/`failed` déjà terminal ne doit surtout pas être réécrit : son
    `error_message` porte l'information lue par le cooldown (quota épuisé, ou
    simple erreur technique).
    """
    active_research = [
        ResearchJob(tenant_id=test_tenant.id, trigger_type="scheduled", status=s)
        for s in ("pending", "processing")
    ]
    finished_research = [
        ResearchJob(tenant_id=test_tenant.id, trigger_type="scheduled", status=s)
        for s in ("done", "failed")
    ]
    active_collection = ResearchCollectionJob(
        tenant_id=test_tenant.id, status="processing", params={}
    )
    done_collection = ResearchCollectionJob(
        tenant_id=test_tenant.id, status="done", params={}
    )
    db_session.add_all(
        active_research + finished_research + [active_collection, done_collection]
    )
    await db_session.commit()

    closed = await fail_orphan_jobs(db_session)
    assert closed == 3

    for job in active_research + [active_collection]:
        await db_session.refresh(job)
        assert job.status == "failed"
        assert job.finished_at is not None
        assert job.error_message.startswith(INTERRUPTED_PREFIX)

    for job in finished_research + [done_collection]:
        await db_session.refresh(job)
        assert job.status in ("done", "failed")
        assert not (job.error_message or "").startswith(INTERRUPTED_PREFIX)


@pytest.mark.asyncio
async def test_fail_orphan_jobs_is_a_noop_without_active_jobs(db_session, test_tenant):
    assert await fail_orphan_jobs(db_session) == 0


@pytest.mark.asyncio
async def test_fail_orphan_jobs_is_idempotent(db_session, test_tenant):
    """Relancer le nettoyage ne referme rien une seconde fois.

    Le lifespan tourne à chaque démarrage : un job déjà `failed` ne doit pas
    être recompté, sinon le compteur de logs mentirait.
    """
    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id, trigger_type="collection", status="pending"
        )
    )
    await db_session.commit()

    assert await fail_orphan_jobs(db_session) == 1
    assert await fail_orphan_jobs(db_session) == 0


@pytest.mark.asyncio
async def test_fail_orphan_jobs_spans_all_tenants(
    db_session, test_tenant, other_tenant
):
    """Le nettoyage est global : aucun tenant ne doit rester bloqué, admin ou non."""
    db_session.add_all(
        [
            ResearchJob(
                tenant_id=test_tenant.id, trigger_type="collection", status="pending"
            ),
            ResearchCollectionJob(
                tenant_id=other_tenant.id, status="pending", params={}
            ),
        ]
    )
    await db_session.commit()

    assert await fail_orphan_jobs(db_session) == 2
@pytest.mark.asyncio
async def test_startup_cleanup_never_raises(monkeypatch, caplog):
    """Une base indisponible au démarrage ne doit pas empêcher le serveur de boot.

    Mieux vaut des jobs orphelins (rattrapables au prochain redémarrage) qu'une
    API qui ne répond plus.
    """
    from app.main import _fail_orphan_jobs_on_startup

    async def _boom(db):
        raise RuntimeError("base indisponible")

    monkeypatch.setattr("app.services.orphan_jobs_service.fail_orphan_jobs", _boom)

    await _fail_orphan_jobs_on_startup()  # ne doit pas lever

    # L'échec doit rester visible dans les logs, pas être silencieusement avalé.
    assert "Nettoyage des jobs de recherche orphelins en échec" in caplog.text


@pytest.mark.asyncio
async def test_startup_cleanup_closes_orphans(db_session, test_tenant):
    """Le helper du lifespan ferme bien les jobs actifs, préfixe compris."""
    from app.main import _fail_orphan_jobs_on_startup

    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id, trigger_type="collection", status="pending"
        )
    )
    await db_session.commit()

    await _fail_orphan_jobs_on_startup()

    # Relu par une requête : le helper travaille dans SA propre session
    # (AsyncSessionLocal), pas celle du test.
    job = (
        await db_session.execute(
            select(ResearchJob).where(ResearchJob.tenant_id == test_tenant.id)
        )
    ).scalars().first()
    assert job.status == "failed"
    assert job.error_message.startswith(INTERRUPTED_PREFIX)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "error_message, expected_status",
    [("interrupted: le serveur a redémarré", 202), ("erreur technique", 429)],
)
async def test_manual_refresh_cooldown_ignores_only_interrupted_failures(
    client,
    admin_headers,
    test_tenant,
    db_session,
    monkeypatch,
    error_message,
    expected_status,
):
    """Seul `interrupted:` est exclu du cooldown ; une erreur technique reste bloquante.

    Le cas 429 est le contrôle négatif indispensable : sans lui, une exclusion
    trop large (par exemple tout job `failed`) passerait le test et
    supprimerait silencieusement le rate-limit mensuel.
    """

    async def _no_pipeline(research_job_id):
        return

    monkeypatch.setattr(
        "app.api.v1.endpoints.tenants._run_research_pipeline", _no_pipeline
    )

    db_session.add(
        ResearchJob(
            tenant_id=test_tenant.id,
            trigger_type="manual_refresh",
            status="failed",
            error_message=error_message,
        )
    )
    await db_session.commit()

    response = await client.post(
        f"/api/v1/tenants/{test_tenant.id}/research/run",
        headers=admin_headers,
        json={"trigger_type": "manual_refresh"},
    )
    assert response.status_code == expected_status