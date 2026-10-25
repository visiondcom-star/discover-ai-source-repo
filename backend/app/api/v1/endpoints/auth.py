"""Authentication endpoints."""
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status, Header, Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.database import get_db
from app.models import User, Tenant
from app.schemas import UserRegister, UserLogin, Token, UserResponse, UserUpdate
from app.config import get_settings
from app.core.security import get_password_hash, verify_password, create_access_token
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user, generate_csrf_token, require_csrf, get_partner_poi_ids

router = APIRouter()

settings = get_settings()
# Cookie flags: `Secure` only in production so the local HTTP (dev) flow works.
_COOKIE_SECURE = settings.ENV.strip().lower() == "production"
_AUTH_COOKIE = "access_token"
_CSRF_COOKIE = "csrf_token"
# Kept in sync with ACCESS_TOKEN_EXPIRE_MINUTES (seconds).
_COOKIE_MAX_AGE = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    data: UserRegister,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    # Check if user exists in this tenant
    result = await db.execute(
        select(User).where(and_(User.email == data.email, User.tenant_id == tenant.id))
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered in this tenant")

    user = User(
        tenant_id=tenant.id,
        email=data.email,
        hashed_password=get_password_hash(data.password),
        full_name=data.full_name,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/login", response_model=Token)
async def login(
    data: UserLogin,
    response: Response,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
):
    tenant = await get_tenant_from_header(x_tenant_slug)

    result = await db.execute(
        select(User).where(
            and_(User.email == data.email, User.tenant_id == tenant.id, User.is_active == True)
        )
    )
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    access_token = create_access_token(
        data={"sub": str(user.id), "tenant": tenant.slug, "email": user.email}
    )

    # Web: authenticate via HttpOnly cookie (Secure only in production; SameSite=Lax
    # blocks cross-site sends while keeping same-site navigation). A separate NON
    # -HttpOnly `csrf_token` cookie backs the double-submit CSRF guard.
    response.set_cookie(
        key=_AUTH_COOKIE,
        value=access_token,
        httponly=True,
        secure=_COOKIE_SECURE,
        samesite="lax",
        max_age=_COOKIE_MAX_AGE,
        path="/",
    )
    response.set_cookie(
        key=_CSRF_COOKIE,
        value=generate_csrf_token(),
        httponly=False,
        secure=_COOKIE_SECURE,
        samesite="lax",
        max_age=_COOKIE_MAX_AGE,
        path="/",
    )

    # Mobile still relies on the Bearer token in the body (flutter_secure_storage
    # owns it); both mechanisms branch on the same underlying JWT and coexist.
    return Token(
        access_token=access_token,
        token_type="bearer",
        expires_in=60 * 24,
    )


@router.post("/logout", dependencies=[Depends(require_csrf)])
async def logout(response: Response):
    # Stateless JWT session: there is no server-side store to revoke, so this only
    # clears the client cookies (Set-Cookie; Max-Age=0). KNOWN LIMITATION: a token
    # already copied to a Bearer client (mobile) remains valid until its natural
    # `exp`; cookie-authenticated web sessions are fully terminated here.
    response.delete_cookie(_AUTH_COOKIE, path="/")
    response.delete_cookie(_CSRF_COOKIE, path="/")
    return {"detail": "Logged out"}


@router.get("/me", response_model=UserResponse)
async def get_me(
    current_user: User = Depends(get_current_user),
    poi_ids: set = Depends(get_partner_poi_ids),
):
    """Profil de l'utilisateur courant.

    `is_partner` reflète le rattachement à au moins un POI du tenant
    (`poi_managers`), via la dépendance `get_partner_poi_ids` déjà utilisée par
    les endpoints partenaire — aucune logique de rôle dupliquée. Ce n'est pas un
    attribut ORM de `User` : on l'injecte à la construction de la réponse.
    """
    response = UserResponse.model_validate(current_user)
    return response.model_copy(update={"is_partner": bool(poi_ids)})


@router.patch("/me", response_model=UserResponse)
async def update_me(
    data: UserUpdate,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(...),
    current_user: User = Depends(get_current_user),
    poi_ids: set = Depends(get_partner_poi_ids),
):
    """Mise à jour du profil (locale, nom, préférences).

    La locale doit appartenir à tenant.supported_languages lorsqu'elle est fournie.
    """
    tenant = await get_tenant_from_header(x_tenant_slug)
    update_data = data.model_dump(exclude_unset=True)

    if "locale" in update_data and update_data["locale"] is not None:
        target_locale = update_data["locale"].strip().lower()
        supported = tenant.supported_languages or []
        if target_locale not in supported:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Locale '{target_locale}' not supported. Supported: {supported}",
            )
        current_user.locale = target_locale

    if "full_name" in update_data:
        current_user.full_name = update_data["full_name"]

    if "preferences" in update_data and update_data["preferences"] is not None:
        merged = dict(current_user.preferences or {})
        merged.update(update_data["preferences"])
        current_user.preferences = merged

    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)

    response = UserResponse.model_validate(current_user)
    return response.model_copy(update={"is_partner": bool(poi_ids)})
