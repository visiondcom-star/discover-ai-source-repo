"""Tests pour la configuration des sources de recherche (ResearchSourceConfig),

validation country_code, résolution hiérarchique (tenant/pays), CRUD et isolation multi-tenant.
"""
import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Tenant, ResearchSourceConfig
from app.schemas import (
    ResearchSourceConfigCreate,
    ResearchSourceConfigUpdate,
    TenantUpdate,
)
from app.services.research_source_service import (
    normalize_url,
    resolve_sources,
    create_tenant_source,
    create_country_source,
    DuplicateSourceError,
)


def test_country_code_normalization_and_validation():
    # Normalisation en majuscules
    t1 = Tenant(slug="t1", name="Tenant 1", country_code="dz", default_currency="DZD")
    assert t1.country_code == "DZ"

    # None est accepté
    t2 = Tenant(slug="t2", name="Tenant 2", country_code=None, default_currency="DZD")
    assert t2.country_code is None

    # DZA rejeté (3 lettres au lieu de 2)
    with pytest.raises(ValueError, match="exactement 2 lettres ASCII"):
        Tenant(slug="t3", name="Tenant 3", country_code="DZA", default_currency="DZD")

    # "1" rejeté (chiffre et longueur 1)
    with pytest.raises(ValueError, match="exactement 2 lettres ASCII"):
        Tenant(slug="t4", name="Tenant 4", country_code="1", default_currency="DZD")

    # Non-ASCII rejeté
    with pytest.raises(ValueError, match="exactement 2 lettres ASCII"):
        Tenant(slug="t5", name="Tenant 5", country_code="éà", default_currency="DZD")


def test_schema_country_code_normalization():
    update = TenantUpdate(country_code="dz")
    assert update.country_code == "DZ"

    update_none = TenantUpdate(country_code=None)
    assert update_none.country_code is None

    with pytest.raises(Exception):
        TenantUpdate(country_code="DZA")

    with pytest.raises(Exception):
        TenantUpdate(country_code="1")


def test_research_source_config_exclusivity():
    tid = uuid.uuid4()
    # OK: tenant seul
    s1 = ResearchSourceConfig(name="S1", url="https://example.com/s1", tenant_id=tid)
    assert s1.tenant_id == tid
    assert s1.country_code is None

    # OK: pays seul
    s2 = ResearchSourceConfig(name="S2", url="https://example.com/s2", country_code="fr")
    assert s2.country_code == "FR"
    assert s2.tenant_id is None

    # Rejeté: les deux
    with pytest.raises(ValueError, match="soit à un tenant soit à un pays"):
        ResearchSourceConfig(name="S3", url="https://example.com/s3", tenant_id=tid, country_code="FR")

    # Rejeté: aucun des deux
    with pytest.raises(ValueError, match="soit à un tenant soit à un pays"):
        ResearchSourceConfig(name="S4", url="https://example.com/s4")


def test_normalize_url():
    assert normalize_url("https://EXAMPLE.COM/path/to/page/") == "https://example.com/path/to/page"
    assert normalize_url("http://example.com:8080/foo#section") == "http://example.com:8080/foo"
    assert normalize_url("https://example.com/") == "https://example.com"


@pytest.mark.asyncio
async def test_resolve_sources(db_session: AsyncSession):
    t_dz = Tenant(slug="dz-tenant", name="Algeria Tenant", country_code="DZ", default_currency="DZD")
    t_tn = Tenant(slug="tn-tenant", name="Tunisia Tenant", country_code="TN", default_currency="TND")
    t_none = Tenant(slug="none-tenant", name="No Country Tenant", country_code=None, default_currency="EUR")
    db_session.add_all([t_dz, t_tn, t_none])
    await db_session.commit()
    await db_session.refresh(t_dz)
    await db_session.refresh(t_tn)
    await db_session.refresh(t_none)

    await create_country_source(
        db_session, "DZ", ResearchSourceConfigCreate(name="Country DZ 1", url="https://ont.dz/info")
    )
    await create_country_source(
        db_session, "DZ", ResearchSourceConfigCreate(name="Country DZ 2", url="https://algeria.travel/")
    )
    await create_country_source(
        db_session, "TN", ResearchSourceConfigCreate(name="Country TN 1", url="https://tunisiatourism.info")
    )

    resolved_dz = await resolve_sources(db_session, t_dz)
    urls_dz = [s.url for s in resolved_dz]
    assert len(resolved_dz) == 2
    assert "https://ont.dz/info" in urls_dz
    assert "https://algeria.travel/" in urls_dz

    # Source pays désactivée au niveau national (enabled=False)
    await create_country_source(
        db_session,
        "DZ",
        ResearchSourceConfigCreate(
            name="Country DZ Inactive",
            url="https://inactive-dz-source.com",
            enabled=False,
        ),
    )
    resolved_dz_inactive_check = await resolve_sources(db_session, t_dz)
    urls_dz_inactive_check = [s.url for s in resolved_dz_inactive_check]
    assert "https://inactive-dz-source.com" not in urls_dz_inactive_check

    resolved_none = await resolve_sources(db_session, t_none)
    assert len(resolved_none) == 0

    s_tenant_override = await create_tenant_source(
        db_session,
        t_dz.id,
        ResearchSourceConfigCreate(name="Tenant DZ Custom Override", url="https://ont.dz/info/"),
    )
    resolved_dz_2 = await resolve_sources(db_session, t_dz)
    assert len(resolved_dz_2) == 2
    matched_override = [s for s in resolved_dz_2 if normalize_url(s.url) == "https://ont.dz/info"]
    assert len(matched_override) == 1
    assert matched_override[0].id == s_tenant_override.id
    assert matched_override[0].name == "Tenant DZ Custom Override"

    await create_tenant_source(
        db_session,
        t_dz.id,
        ResearchSourceConfigCreate(
            name="Tenant Disable Algeria Travel",
            url="https://algeria.travel",
            enabled=False,
        ),
    )
    resolved_dz_3 = await resolve_sources(db_session, t_dz)
    urls_dz_3 = [normalize_url(s.url) for s in resolved_dz_3]
    assert "https://algeria.travel" not in urls_dz_3
    assert len(resolved_dz_3) == 1

    await create_tenant_source(
        db_session,
        t_tn.id,
        ResearchSourceConfigCreate(name="TN specific", url="https://custom.tn"),
    )
    resolved_dz_4 = await resolve_sources(db_session, t_dz)
    urls_dz_4 = [normalize_url(s.url) for s in resolved_dz_4]
    assert "https://custom.tn" not in urls_dz_4


@pytest.mark.asyncio
async def test_duplicate_source_refused(db_session: AsyncSession, test_tenant: Tenant):
    await create_tenant_source(
        db_session,
        test_tenant.id,
        ResearchSourceConfigCreate(name="S1", url="https://example.com/docs/"),
    )

    with pytest.raises(DuplicateSourceError):
        await create_tenant_source(
            db_session,
            test_tenant.id,
            ResearchSourceConfigCreate(name="S2", url="https://example.com/docs"),
        )


@pytest.mark.asyncio
async def test_api_crud_and_isolation(
    client: AsyncClient,
    admin_headers: dict,
    other_admin_headers: dict,
    test_tenant: Tenant,
    other_tenant: Tenant,
):
    base_url = f"/api/v1/tenants/{test_tenant.id}/research/sources"
    other_base_url = f"/api/v1/tenants/{other_tenant.id}/research/sources"

    res = await client.get(base_url, headers=admin_headers)
    assert res.status_code == 200
    assert res.json() == []

    res_invalid_url = await client.post(
        base_url,
        headers=admin_headers,
        json={"name": "Bad URL", "url": "ftp://files.example.com"},
    )
    assert res_invalid_url.status_code == 422

    payload = {
        "name": "Office Tourisme Alger",
        "url": "https://alger-tourisme.dz",
        "source_type": "office_tourisme",
        "enabled": True,
        "config": {"max_depth": 2},
    }
    res_create = await client.post(base_url, headers=admin_headers, json=payload)
    assert res_create.status_code == 201
    source_data = res_create.json()
    source_id = source_data["id"]
    assert source_data["name"] == "Office Tourisme Alger"
    assert source_data["tenant_id"] == str(test_tenant.id)
    assert source_data["country_code"] is None

    res_dup = await client.post(
        base_url,
        headers=admin_headers,
        json={"name": "Doublon", "url": "https://alger-tourisme.dz/"},
    )
    assert res_dup.status_code == 409

    res_other_list = await client.get(other_base_url, headers=other_admin_headers)
    assert res_other_list.status_code == 200
    assert res_other_list.json() == []

    res_other_patch = await client.patch(
        f"{other_base_url}/{source_id}",
        headers=other_admin_headers,
        json={"name": "Hacked"},
    )
    assert res_other_patch.status_code == 404

    res_other_delete = await client.delete(
        f"{other_base_url}/{source_id}",
        headers=other_admin_headers,
    )
    assert res_other_delete.status_code == 404

    res_patch = await client.patch(
        f"{base_url}/{source_id}",
        headers=admin_headers,
        json={"name": "Office Tourisme Alger (Mis à jour)", "enabled": False},
    )
    assert res_patch.status_code == 200
    assert res_patch.json()["name"] == "Office Tourisme Alger (Mis à jour)"
    assert res_patch.json()["enabled"] is False

    res_delete = await client.delete(
        f"{base_url}/{source_id}",
        headers=admin_headers,
    )
    assert res_delete.status_code == 204

    res_get_deleted = await client.patch(
        f"{base_url}/{source_id}",
        headers=admin_headers,
        json={"name": "Test"},
    )
    assert res_get_deleted.status_code == 404

    # 9. Test update doublon URL -> 409
    res_second = await client.post(
        base_url,
        headers=admin_headers,
        json={"name": "Source 2", "url": "https://source2.dz"},
    )
    assert res_second.status_code == 201
    source_2_id = res_second.json()["id"]

    res_third = await client.post(
        base_url,
        headers=admin_headers,
        json={"name": "Source 3", "url": "https://source3.dz"},
    )
    assert res_third.status_code == 201
    source_3_id = res_third.json()["id"]

    # Tentative d'updater source 3 pour prendre l'URL de source 2
    res_dup_patch = await client.patch(
        f"{base_url}/{source_3_id}",
        headers=admin_headers,
        json={"url": "https://source2.dz/"},
    )
    assert res_dup_patch.status_code == 409
    # 10. Test rejet des nulls explicites dans PATCH (ex: {"name": null}) -> 422
    for null_payload in [
        {"name": None},
        {"url": None},
        {"source_type": None},
        {"enabled": None},
        {"config": None},
    ]:
        res_null = await client.patch(
            f"{base_url}/{source_2_id}",
            headers=admin_headers,
            json=null_payload,
        )
        assert res_null.status_code == 422, f"Payload {null_payload} should return 422 Unprocessable Entity"
    # 11. Test injection tenant_id et country_code dans PATCH
    res_tamper = await client.patch(
        f"{base_url}/{source_2_id}",
        headers=admin_headers,
        json={
            "name": "Tamper Attempt",
            "tenant_id": str(other_tenant.id),
            "country_code": "DZ",
        },
    )
    assert res_tamper.status_code == 200
    tamper_json = res_tamper.json()
    assert tamper_json["name"] == "Tamper Attempt"
    assert tamper_json["tenant_id"] == str(test_tenant.id)
    assert tamper_json["country_code"] is None

    # Vérification en base que la source a bien gardé son tenant_id d'origine et country_code=None
    res_verify_source = await client.get(f"{base_url}", headers=admin_headers)
    assert res_verify_source.status_code == 200
    sources_tenant_1 = res_verify_source.json()
    tampered_source = next(s for s in sources_tenant_1 if s["id"] == str(source_2_id))
    assert tampered_source["tenant_id"] == str(test_tenant.id)
    assert tampered_source["country_code"] is None

    # La liste des sources de l'autre tenant doit rester strictement vide
    res_other_list_after_tamper = await client.get(other_base_url, headers=other_admin_headers)
    assert res_other_list_after_tamper.status_code == 200
    assert res_other_list_after_tamper.json() == []



