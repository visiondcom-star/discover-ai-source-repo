"""Tests du service de quota contre un vrai Postgres (ce que FakeDB ne peut pas prouver).

Ce qui ne se vérifie qu'en base : les défauts de colonne réellement appliqués à l'INSERT, et le
comportement quand plusieurs appels IA simultanés visent un tenant qui n'a encore jamais eu de
ligne de quota (vraie violation de clé primaire sur `tenant_id`, pas une exception simulée).

L'entrelacement est forcé par une barrière sur le `commit` : un simple `asyncio.gather` ne reproduit
pas la course (mesuré : **0** conflit — le temps d'établir les connexions TCP dépasse la durée de la
transaction gagnante, si bien que les appels suivants lisent déjà la ligne créée). Le test de course
compte donc lui-même les conflits réellement rejetés par Postgres (écouteur `handle_error` branché sur
le moteur) et échoue si la course n'a pas eu lieu : il ne peut pas passer en ne testant rien.
"""
import asyncio
from datetime import timedelta

from sqlalchemy import event, func, select
from sqlalchemy.exc import IntegrityError

import app.database as db_module
import app.services.tenant_ai_quota_service as svc
from app.models import TenantAIQuotaConfig

RACE_CONCURRENCY = 6
RACE_TIMEOUT_S = 30


class Gate:
    """Barrière : retient chaque commit jusqu'à ce que `n` appels y soient arrivés."""

    def __init__(self, n):
        self.n = n
        self.arrived = 0
        self.event = asyncio.Event()

    async def wait(self):
        self.arrived += 1
        if self.arrived >= self.n:
            self.event.set()
        await self.event.wait()


class GatedSession:
    """Proxy de session : `commit` passe par la barrière, `rollback` est compté."""

    def __init__(self, session, gate):
        self._session = session
        self._gate = gate
        self.rolled_back = False

    def __getattr__(self, name):
        return getattr(self._session, name)

    async def commit(self):
        await self._gate.wait()
        await self._session.commit()

    async def rollback(self):
        self.rolled_back = True
        await self._session.rollback()


def _watch_integrity_errors(engine):
    """Vérité terrain : tout refus remonté par le driver passe ici, y compris les conflits que le
    service absorbe ensuite (il ne peut donc pas « cacher » qu'une course a eu lieu).
    Renvoie la liste des statements concernés + la fonction de désabonnement."""
    seen = []

    def _on_error(context):
        exc = getattr(context, "sqlalchemy_exception", None) or context.original_exception
        if isinstance(exc, IntegrityError):
            seen.append(str(getattr(context, "statement", ""))[:60])

    event.listen(engine.sync_engine, "handle_error", _on_error)
    return seen, lambda: event.remove(engine.sync_engine, "handle_error", _on_error)


async def _count_quota_rows() -> int:
    async with db_module.AsyncSessionLocal() as session:
        return await session.scalar(select(func.count()).select_from(TenantAIQuotaConfig))


async def test_creation_applies_the_column_defaults(db_session, test_tenant):
    config = await svc.get_or_create_quota_config(db_session, test_tenant.id)

    assert config.tenant_id == test_tenant.id
    assert config.quota_metric == "usd_cost"
    assert config.monthly_limit == 50          # 50 USD/mois
    assert config.current_period_usage == 0
    assert config.soft_limit_threshold_pct == 80
    assert config.soft_limit_alert_sent is False
    assert config.hard_limit_enforced is True  # hard limit actif par défaut
    assert config.current_period_end - config.current_period_start == timedelta(days=30)


async def test_second_call_returns_the_same_row_without_duplicating(db_session, test_tenant):
    first = await svc.get_or_create_quota_config(db_session, test_tenant.id)
    second = await svc.get_or_create_quota_config(db_session, test_tenant.id)

    assert second.tenant_id == first.tenant_id
    assert await _count_quota_rows() == 1


async def test_simultaneous_first_calls_all_succeed_and_absorb_real_conflicts(test_tenant):
    """Le pire cas : plusieurs appels IA atteignent le commit en même temps pour un tenant sans
    ligne de quota (barrière sur `commit` : tous les SELECT précèdent tous les INSERT).

    Le test prouve lui-même qu'il déclenche bien la course, et pas seulement que « ça marche » :
      * `gate.arrived == N` -> les N appels étaient bien au même point de commit ;
      * `len(conflicts) == N - 1` -> Postgres a réellement rejeté N-1 INSERT (compteur branché sur
        le moteur SQLAlchemy, impossible à masquer par le service) ;
      * `rolled_back == N - 1` -> chaque conflit a été absorbé par le rollback + relecture.

    Si la stratégie change (p. ex. `INSERT ... ON CONFLICT DO NOTHING`, qui absorbe le conflit côté
    Postgres sans lever d'exception), c'est l'assertion sur `conflicts` qu'il faut adapter : l'attente
    fonctionnelle, elle, ne bouge pas (les N appels réussissent, une seule ligne est créée).
    """
    gate = Gate(RACE_CONCURRENCY)
    proxies = []
    conflicts, stop_watching = _watch_integrity_errors(db_module.engine)

    async def first_call():
        async with db_module.AsyncSessionLocal() as session:
            proxy = GatedSession(session, gate)
            proxies.append(proxy)
            return await svc.get_or_create_quota_config(proxy, test_tenant.id)

    try:
        results = await asyncio.wait_for(
            asyncio.gather(*(first_call() for _ in range(RACE_CONCURRENCY))),
            timeout=RACE_TIMEOUT_S,
        )
    finally:
        stop_watching()

    # Preuve que la course a bien été déclenchée — sinon ce test ne prouverait rien.
    assert gate.arrived == RACE_CONCURRENCY, "les appels n'ont pas été synchronisés au commit"
    assert len(conflicts) == RACE_CONCURRENCY - 1, "aucun conflit de clé primaire : course non atteinte"
    assert sum(1 for proxy in proxies if proxy.rolled_back) == RACE_CONCURRENCY - 1

    # Comportement attendu côté appelant : aucun appel ne subit le conflit.
    assert len(results) == RACE_CONCURRENCY
    assert {config.tenant_id for config in results} == {test_tenant.id}
    assert all(config.monthly_limit == 50 for config in results)  # défauts, pas des NULL
    assert all(config.current_period_usage == 0 for config in results)
    assert await _count_quota_rows() == 1
