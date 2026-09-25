"""Tests de l'isolation tenant dans get_current_user (sans base de données réelle).

On simule db.execute : le 1er appel du code (select User) renvoie l'utilisateur,
le 2e (select Tenant) renvoie le tenant. Ordre fixé par l'implémentation actuelle.
"""
import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

import app.dependencies as deps

TENANT_A = uuid.uuid4()
TENANT_B = uuid.uuid4()


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class FakeDB:
    """Renvoie les résultats fournis dans l'ordre des appels à execute()."""

    def __init__(self, *results):
        self._results = list(results)
        self.calls = 0

    async def execute(self, _stmt):
        self.calls += 1
        return _ScalarResult(self._results.pop(0))


def _credentials(token="tok"):
    return SimpleNamespace(credentials=token)


async def _run(monkeypatch, db, x_tenant_slug, payload):
    monkeypatch.setattr(deps, "decode_token", lambda t: payload)
    return await deps.get_current_user(
        credentials=_credentials(),
        request=None,
        db=db,
        x_tenant_slug=x_tenant_slug,
    )


async def test_matching_tenant_is_accepted(monkeypatch):
    user = SimpleNamespace(id="u1", is_active=True, tenant_id=TENANT_A)
    tenant = SimpleNamespace(id=TENANT_A, slug="acme")
    db = FakeDB(user, tenant)

    result = await _run(monkeypatch, db, "acme", {"sub": "u1", "tenant": "acme"})

    assert result is user
    assert db.calls == 2


async def test_user_of_another_tenant_is_rejected_even_with_no_tenant_claim(monkeypatch):
    """Le token n'a pas de champ 'tenant' (ex : futur flux d'émission) : la vérification
    historique (token_tenant vs header) est ignorée, mais la nouvelle vérification en
    base doit quand même bloquer l'accès."""
    user = SimpleNamespace(id="u1", is_active=True, tenant_id=TENANT_B)
    tenant_from_slug = SimpleNamespace(id=TENANT_A, slug="acme")
    db = FakeDB(user, tenant_from_slug)

    with pytest.raises(HTTPException) as exc:
        await _run(monkeypatch, db, "acme", {"sub": "u1"})  # pas de "tenant" dans le payload

    assert exc.value.status_code == 403
    assert exc.value.detail == deps.TENANT_MISMATCH_DETAIL


async def test_token_tenant_claim_alone_does_not_bypass_the_db_check(monkeypatch):
    """Même si le token prétend appartenir au bon tenant, si user.tenant_id (en base)
    dit le contraire, l'accès doit être refusé."""
    user = SimpleNamespace(id="u1", is_active=True, tenant_id=TENANT_B)
    tenant_from_slug = SimpleNamespace(id=TENANT_A, slug="acme")
    db = FakeDB(user, tenant_from_slug)

    with pytest.raises(HTTPException) as exc:
        await _run(monkeypatch, db, "acme", {"sub": "u1", "tenant": "acme"})

    assert exc.value.status_code == 403


async def test_unknown_slug_raises_404_before_tenant_comparison(monkeypatch):
    user = SimpleNamespace(id="u1", is_active=True, tenant_id=TENANT_A)
    db = FakeDB(user, None)  # aucun tenant pour ce slug

    with pytest.raises(HTTPException) as exc:
        await _run(monkeypatch, db, "inconnu", {"sub": "u1"})

    assert exc.value.status_code == 404


async def test_inactive_user_still_rejected_before_tenant_check(monkeypatch):
    user = SimpleNamespace(id="u1", is_active=False, tenant_id=TENANT_A)
    db = FakeDB(user)  # un seul résultat : la vérification tenant ne doit jamais être atteinte

    with pytest.raises(HTTPException) as exc:
        await _run(monkeypatch, db, "acme", {"sub": "u1"})

    assert exc.value.status_code == 404
    assert db.calls == 1
