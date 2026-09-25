"""FastAPI dependencies for auth, DB, tenant, and CSRF protection."""
from uuid import UUID
import secrets
from typing import Optional

from fastapi import Depends, HTTPException, Request, status, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import User, Tenant
from app.core.security import decode_token
from app.core.tenant import get_tenant_from_header

TENANT_MISMATCH_DETAIL = "Tenant mismatch"

security = HTTPBearer(auto_error=False)

# ---- CSRF (double-submit cookie) helpers -------------------------------------
# The web client authenticates via an HttpOnly `access_token` cookie, so those
# requests are authenticated by a browser-managed credential that a malicious
# cross-origin site could make the browser attach implicitly. To neutralise that
# (CSRF), login also issues a NON-HttpOnly `csrf_token` cookie containing a
# random value; the SPA must echo it back in the `X-CSRF-Token` header on every
# state-changing request. The backend compares both.
CSRF_COOKIE = "csrf_token"
CSRF_HEADER = "X-CSRF-Token"


def generate_csrf_token() -> str:
    """A fresh, cryptographically random CSRF value (url-safe, unguessable)."""
    return secrets.token_urlsafe(32)


async def require_csrf(request: Request) -> None:
    """Reusable double-submit CSRF guard, applied router-wide (never per endpoint).

    Only meaningful for cookie-authenticated browser sessions:
    - GET/HEAD/OPTIONS are never checked (CSRF only concerns state changes).
    - If the client supplied explicit ``Authorization`` credentials (mobile
      Bearer flow), the request is not a cookie-authenticated browser session and
      CSRF does not apply: a cross-site form cannot inject that header, so the
      request is not exploitable.
    - If no ``csrf_token`` cookie is present (anonymous register, first login,
      native clients), there is nothing to guard.
    - Otherwise (web, authenticated via cookie) the ``X-CSRF-Token`` header MUST
      match the cookie value, else 403.
    """
    if request.method in ("GET", "HEAD", "OPTIONS"):
        return
    # A Bearer credential in the header means this request is not relying on a
    # browser-managed authentication cookie, so the double-submit cookie is
    # neither required nor meaningful.
    if request.headers.get("authorization"):
        return

    cookie_token = request.cookies.get(CSRF_COOKIE)
    if cookie_token is None:
        return

    header_token = request.headers.get(CSRF_HEADER)
    if not header_token or not secrets.compare_digest(header_token.strip(), cookie_token):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="CSRF token missing or invalid",
        )


# ---- Authentication -----------------------------------------------------------
async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
) -> User:
    # Mobile: `Authorization: Bearer <token>`. Web: HttpOnly cookie. Bearer wins
    # when present (keeps the existing mobile/Bearer tests and callers intact).
    token: Optional[str] = None
    if credentials is not None:
        token = credentials.credentials
    else:
        token = request.cookies.get("access_token")

    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    # Verify tenant match
    token_tenant = payload.get("tenant")
    if token_tenant and token_tenant != x_tenant_slug:
        raise HTTPException(status_code=403, detail="Tenant mismatch")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user or not user.is_active:
        raise HTTPException(status_code=404, detail="User not found")

    # Défense en profondeur : la vérification ci-dessus ne compare que deux valeurs
    # fournies par l'appelant (le token et l'en-tête). Ici on ancre la décision dans
    # ce que la base sait réellement de l'utilisateur (user.tenant_id), pour rester
    # protégé même si un futur flux émet un token sans revendication "tenant".
    tenant_result = await db.execute(select(Tenant).where(Tenant.slug == x_tenant_slug))
    request_tenant = tenant_result.scalar_one_or_none()
    if not request_tenant:
        raise HTTPException(status_code=404, detail=f"Tenant '{x_tenant_slug}' not found")
    if user.tenant_id != request_tenant.id:
        raise HTTPException(status_code=403, detail=TENANT_MISMATCH_DETAIL)

    return user


async def get_current_active_user(
    current_user: User = Depends(get_current_user),
) -> User:
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


async def get_current_admin(
    current_user: User = Depends(get_current_user),
) -> User:
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user


async def get_tenant_admin(
    tenant_id: UUID,
    current_admin: User = Depends(get_current_admin),
) -> User:
    """Admin autorisé à agir sur le tenant visé par l'URL (/{tenant_id}/...).

    Un admin n'administre que son propre tenant. Le 404 (et non 403) évite de
    révéler l'existence d'un autre tenant.
    """
    if str(current_admin.tenant_id) != str(tenant_id):
        raise HTTPException(status_code=404, detail="Tenant not found")
    return current_admin
