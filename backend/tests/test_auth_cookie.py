"""Cookie-auth + CSRF tests — migration of live token from localStorage to HttpOnly cookie.

Covers:
- login still returns the Bearer token in the body (mobile flow untouched) AND sets
  the HttpOnly `access_token` cookie + non-HttpOnly `csrf_token` cookie.
- get_current_user accepts the HttpOnly cookie (no Authorization header).
- CSRF double-submit: mutating cookie-authenticated request without X-CSRF-Token
  -> 403; with the matching header -> success; Bearer requests skip CSRF.
- logout clears the cookies (Max-Age=0) and the session is then unauthorised.
"""
import pytest


async def _login(client, tenant_slug="test-tenant"):
    """Log a known user in and return the raw response (jars cookies on client)."""
    return await client.post(
        "/api/v1/auth/login",
        headers={"X-Tenant-Slug": tenant_slug},
        json={"email": "test@example.com", "password": "testpass123"},
    )


@pytest.mark.asyncio
async def test_login_keeps_bearer_body_and_sets_cookies(client, test_user, test_tenant):
    res = await _login(client)
    assert res.status_code == 200

    # Mobile/body flow preserved: the Bearer token is still returned.
    body = res.json()
    assert "access_token" in body
    assert body["token_type"] == "bearer"

    set_cookies = res.headers.get_list("set-cookie")
    joined = "\n".join(set_cookies)
    # HttpOnly access_token cookie (auth).
    assert any("access_token=" in sc and "HttpOnly" in sc for sc in set_cookies), joined
    # Non-HttpOnly csrf_token cookie (must stay readable from JS).
    assert any("csrf_token=" in sc and "HttpOnly" not in sc for sc in set_cookies), joined
    # SameSite=Lax so the auth cookie is never shipped to cross-site origins.
    assert "SameSite=Lax" in joined or "samesite=lax" in joined.lower()


@pytest.mark.asyncio
async def test_get_current_user_accepts_cookie(client, test_user, test_tenant):
    await _login(client)
    me = await client.get("/api/v1/auth/me", headers={"X-Tenant-Slug": "test-tenant"})
    assert me.status_code == 200
    assert me.json()["email"] == "test@example.com"


@pytest.mark.asyncio
async def test_me_without_any_credentials_is_401(client, test_tenant):
    me = await client.get("/api/v1/auth/me", headers={"X-Tenant-Slug": "test-tenant"})
    assert me.status_code == 401


@pytest.mark.asyncio
async def test_mutating_cookie_request_without_csrf_header_is_403(client, test_user, test_tenant):
    await _login(client)  # sets csrf_token + access_token cookies in the jar
    res = await client.post(
        "/api/v1/auth/logout", headers={"X-Tenant-Slug": "test-tenant"}
    )
    # Cookie-authenticated mutating request lacking X-CSRF-Token must be rejected.
    assert res.status_code == 403
    assert "csrf" in res.json()["detail"].lower()


@pytest.mark.asyncio
async def test_mutating_cookie_request_with_csrf_header_succeeds(client, test_user, test_tenant):
    await _login(client)
    csrf = client.cookies.get("csrf_token")
    assert csrf

    res = await client.post(
        "/api/v1/auth/logout",
        headers={"X-Tenant-Slug": "test-tenant", "X-CSRF-Token": csrf},
    )
    assert res.status_code == 200
    assert res.json() == {"detail": "Logged out"}


@pytest.mark.asyncio
async def test_logout_clears_cookies_with_max_age_zero(client, test_user, test_tenant):
    await _login(client)
    csrf = client.cookies.get("csrf_token")
    res = await client.post(
        "/api/v1/auth/logout",
        headers={"X-Tenant-Slug": "test-tenant", "X-CSRF-Token": csrf},
    )
    assert res.status_code == 200
    for sc in res.headers.get_list("set-cookie"):
        assert "Max-Age=0" in sc or ("expires=" in sc.lower())

    # Cookie-authenticated session is gone afterwards.
    me = await client.get("/api/v1/auth/me", headers={"X-Tenant-Slug": "test-tenant"})
    assert me.status_code == 401


@pytest.mark.asyncio
async def test_bearer_mutating_request_skips_csrf(client, test_user, test_tenant):
    """Mobile/Bearer requests do not carry cookies and must not be CSRF-blocked."""
    res = await _login(client)
    token = res.json()["access_token"]
    # No X-CSRF-Token header, Bearer credential only: should NOT be 403.
    res = await client.post(
        "/api/v1/auth/logout",
        headers={
            "X-Tenant-Slug": "test-tenant",
            "Authorization": f"Bearer {token}",
        },
    )
    assert res.status_code == 200