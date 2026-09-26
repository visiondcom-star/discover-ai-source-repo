"""Tests de tenant_ai_quota_service (sans base de données réelle).

FakeDB enregistre les appels : `record_usage` doit incrémenter le compteur par un UPDATE SQL
atomique, jamais par un read-then-write Python, et la création de la ligne de quota doit absorber
la course entre deux appels IA simultanés d'un tenant qui n'a pas encore de ligne (un
`IntegrityError` au commit est suivi d'un rollback et d'une relecture, pas d'un échec).

Ce qui dépend réellement de Postgres (défauts de colonne appliqués à l'INSERT, vraie violation de
clé primaire, appels concurrents) est couvert par `test_tenant_ai_quota_db.py`.
"""
import uuid
from datetime import timedelta
from types import SimpleNamespace

import pytest
from sqlalchemy.exc import IntegrityError, NoResultFound
from sqlalchemy.sql.dml import Update

import app.services.tenant_ai_quota_service as svc
from app.models import utcnow

TENANT = uuid.uuid4()


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value

    def scalar_one(self):
        if self._value is None:
            raise NoResultFound("aucune ligne")
        return self._value


# Défauts de colonne que Postgres applique à l'INSERT (cf. test_tenant_ai_quota_db.py).
COLUMN_DEFAULTS = dict(
    quota_metric="usd_cost",
    monthly_limit=50,
    current_period_usage=0,
    soft_limit_threshold_pct=80,
    soft_limit_alert_sent=False,
    hard_limit_enforced=True,
    billing_cycle_anchor_day=1,
)


class FakeDB:
    """db.execute renvoie les résultats fournis dans l'ordre et conserve les statements
    exécutés ; add/commit/refresh/rollback sont enregistrés sans toucher à une vraie base.
    `commit_error` simule l'IntegrityError d'un INSERT concurrent."""

    def __init__(self, *results, commit_error=None):
        self._results = list(results)
        self._commit_error = commit_error
        self.added = []
        self.executed = []
        self.commits = 0
        self.rollbacks = 0
        self.refreshed = []

    async def execute(self, stmt):
        self.executed.append(stmt)
        return self._results.pop(0) if self._results else None

    def add(self, obj):
        self.added.append(obj)

    async def commit(self):
        self.commits += 1
        if self._commit_error is not None:
            raise self._commit_error

    async def rollback(self):
        self.rollbacks += 1

    async def refresh(self, obj):
        """Les défauts de colonne n'existent qu'après l'INSERT côté Postgres : on simule le
        rechargement, sinon `monthly_limit`/`hard_limit_enforced` resteraient à None."""
        self.refreshed.append(obj)
        for name, value in COLUMN_DEFAULTS.items():
            if getattr(obj, name, None) is None:
                setattr(obj, name, value)


def _integrity_error():
    """Violation de clé primaire telle qu'asyncpg la remonte quand la ligne existe déjà."""
    return IntegrityError(
        "INSERT INTO tenant_ai_quota_configs ...",
        {},
        Exception('duplicate key value violates unique constraint "tenant_ai_quota_configs_pkey"'),
    )


def _quota(**over):
    """Config de quota valide (période non expirée) pour les tests de check_quota."""
    now = utcnow()
    base = dict(
        tenant_id=TENANT,
        quota_metric="usd_cost",
        monthly_limit=50,
        current_period_usage=0,
        soft_limit_threshold_pct=80,
        soft_limit_alert_sent=False,
        hard_limit_enforced=True,
        current_period_start=now,
        current_period_end=now + timedelta(days=5),
    )
    base.update(over)
    return SimpleNamespace(**base)


# --- défauts du modèle ------------------------------------------------------------------------

def test_defaults_are_the_agreed_contract():
    """50 USD/mois, alerte à 80 %, hard limit actif : valeurs créées pour un tenant qui n'a
    encore rien consommé (défauts de colonne, pas du service)."""
    columns = svc.TenantAIQuotaConfig.__table__.c
    assert columns.quota_metric.default.arg == "usd_cost"
    assert columns.monthly_limit.default.arg == 50
    assert columns.current_period_usage.default.arg == 0
    assert columns.soft_limit_threshold_pct.default.arg == 80
    assert columns.soft_limit_alert_sent.default.arg is False
    assert columns.hard_limit_enforced.default.arg is True


# --- get_or_create_quota_config ---------------------------------------------------------------

async def test_get_or_create_creates_a_row_when_none_exists():
    db = FakeDB(_ScalarResult(None))

    config = await svc.get_or_create_quota_config(db, TENANT)

    assert config in db.added
    assert db.commits == 1
    assert db.rollbacks == 0
    assert config.tenant_id == TENANT
    assert config.current_period_end - config.current_period_start == timedelta(days=30)
    # Sans le refresh, les défauts de colonne (appliqués par Postgres à l'INSERT) resteraient None.
    assert config in db.refreshed
    assert config.monthly_limit == 50


async def test_concurrent_creation_is_absorbed_and_the_other_row_is_used():
    """Deux appels IA simultanés du tout premier appel d'un tenant : le second échoue sur la clé
    primaire, annule sa transaction avortée (asyncpg l'exige) puis relit la ligne créée par le
    premier — au lieu de casser l'appel IA de l'utilisateur."""
    winner_row = _quota()
    db = FakeDB(_ScalarResult(None), _ScalarResult(winner_row), commit_error=_integrity_error())

    config = await svc.get_or_create_quota_config(db, TENANT)

    assert config is winner_row
    assert db.rollbacks == 1        # la transaction avortée est bien annulée
    assert db.refreshed == []       # le commit a échoué : rien à recharger
    assert len(db.executed) == 2    # SELECT initial, puis relecture après le conflit


async def test_integrity_error_with_another_cause_is_not_swallowed():
    """Si l'IntegrityError vient d'autre chose (ex. FK : tenant inexistant), la relecture ne trouve
    rien et l'erreur remonte — elle ne passe pas silencieusement pour un succès."""
    db = FakeDB(_ScalarResult(None), _ScalarResult(None), commit_error=_integrity_error())

    with pytest.raises(NoResultFound):
        await svc.get_or_create_quota_config(db, TENANT)
    assert db.rollbacks == 1


async def test_get_or_create_returns_the_existing_row_without_inserting():
    existing = _quota()
    db = FakeDB(_ScalarResult(existing))

    assert await svc.get_or_create_quota_config(db, TENANT) is existing
    assert len(db.executed) == 1  # un seul SELECT, aucun INSERT
    assert db.added == []
    assert db.commits == 0 and db.rollbacks == 0


# --- reset paresseux de période ----------------------------------------------------------------

async def test_expired_period_is_reset_on_the_first_read():
    expired = _quota(
        current_period_start=utcnow() - timedelta(days=31),
        current_period_end=utcnow() - timedelta(days=1),
        current_period_usage=42,
        soft_limit_alert_sent=True,
    )
    db = FakeDB()

    result = await svc._reset_period_if_expired(db, expired)

    assert result is expired
    assert expired.current_period_usage == 0
    assert expired.soft_limit_alert_sent is False
    assert expired.current_period_start <= utcnow() < expired.current_period_end
    assert expired.current_period_end - expired.current_period_start == timedelta(days=30)
    assert db.commits == 1


async def test_valid_period_is_left_untouched():
    valid = _quota(current_period_usage=7, soft_limit_alert_sent=True)
    db = FakeDB()

    assert await svc._reset_period_if_expired(db, valid) is valid
    assert valid.current_period_usage == 7
    assert valid.soft_limit_alert_sent is True
    assert db.commits == 0


# --- check_quota --------------------------------------------------------------------------------

async def test_check_quota_returns_the_config_when_under_the_limit():
    config = _quota(current_period_usage=10)
    db = FakeDB(_ScalarResult(config))

    assert await svc.check_quota(db, TENANT) is config
    assert db.commits == 0  # rien à réinitialiser


async def test_check_quota_raises_when_hard_limit_is_reached():
    config = _quota(current_period_usage=50, monthly_limit=50)
    db = FakeDB(_ScalarResult(config))

    with pytest.raises(svc.QuotaExceededError) as exc:
        await svc.check_quota(db, TENANT)

    assert exc.value.tenant_id == TENANT
    assert exc.value.monthly_limit == 50
    assert exc.value.current_usage == 50


async def test_check_quota_does_not_raise_above_the_limit_without_hard_enforcement():
    """Sans hard limit, le dépassement est signalé par soft_limit_alert_sent, pas bloqué."""
    config = _quota(current_period_usage=80, hard_limit_enforced=False)
    db = FakeDB(_ScalarResult(config))

    assert await svc.check_quota(db, TENANT) is config


async def test_expired_period_does_not_lock_the_tenant_out():
    """Le reset paresseux intervient avant la décision : un dépassement du mois précédent ne
    bloque pas le mois suivant, même avec hard_limit_enforced=True."""
    expired = _quota(
        current_period_start=utcnow() - timedelta(days=31),
        current_period_end=utcnow() - timedelta(days=1),
        current_period_usage=999,
        soft_limit_alert_sent=True,
    )
    db = FakeDB(_ScalarResult(expired))

    assert await svc.check_quota(db, TENANT) is expired
    assert expired.current_period_usage == 0
    assert db.commits == 1


async def test_check_quota_creates_the_row_for_a_never_configured_tenant():
    """Tout premier appel IA d'un tenant : la ligne est créée, les défauts de colonne sont
    rechargés depuis Postgres (cf. test_tenant_ai_quota_db.py), puis 0 < 50 : rien n'est bloqué."""
    db = FakeDB(_ScalarResult(None))

    config = await svc.check_quota(db, TENANT)

    assert config in db.added
    assert config.monthly_limit == 50
    assert config.current_period_usage == 0
    assert config.hard_limit_enforced is True
    assert db.commits == 1  # création seulement : la période n'est pas expirée


# --- record_usage -------------------------------------------------------------------------------

async def test_record_usage_logs_and_increments_atomically():
    db = FakeDB()

    log = await svc.record_usage(
        db, TENANT,
        provider="openai", model="gpt-4o-mini", feature="chat",
        prompt_tokens=10, completion_tokens=5, cached_tokens=2,
        estimated_cost_usd=0.02, latency_ms=120,
    )

    assert log in db.added
    assert log in db.refreshed
    assert db.commits == 1
    assert log.tenant_id == TENANT
    assert log.feature == "chat"
    assert log.total_tokens == 15

    # Un seul statement, un UPDATE d'incrément : ni SELECT ni read-then-write Python.
    assert len(db.executed) == 1
    stmt = db.executed[0]
    assert isinstance(stmt, Update)
    assert "current_period_usage=(" in str(stmt)
    assert stmt.compile().params["current_period_usage_1"] == 0.02


async def test_record_usage_keeps_only_the_stable_error_category():
    db = FakeDB()

    log = await svc.record_usage(
        db, TENANT,
        provider="openai", model="gpt-4o-mini", feature="chat",
        estimated_cost_usd=0, status="quota_exceeded", error_code="rate_limited",
    )

    assert log.status == "quota_exceeded"
    assert log.error_code == "rate_limited"
    assert log.prompt_tokens == 0 and log.completion_tokens == 0


async def test_record_usage_accepts_a_system_call_without_user_or_request():
    db = FakeDB()

    log = await svc.record_usage(
        db, TENANT,
        provider="openai", model="text-embedding-3-small",
        feature="rag_ingestion", estimated_cost_usd=0.0001,
    )

    assert log.user_id is None
    assert log.request_id is None
    assert log.status == "success"


async def test_record_usage_rejects_an_unknown_status_before_writing():
    db = FakeDB()

    with pytest.raises(ValueError):
        await svc.record_usage(
            db, TENANT,
            provider="openai", model="gpt-4o-mini", feature="chat",
            estimated_cost_usd=0.01, status="exploded",
        )

    assert db.added == []
    assert db.executed == []
    assert db.commits == 0
