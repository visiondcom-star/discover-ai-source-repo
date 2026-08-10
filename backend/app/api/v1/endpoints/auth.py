"""Authentication endpoints."""
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.database import get_db
from app.models import User, Tenant
from app.schemas import UserRegister, UserLogin, Token, UserResponse
from app.core.security import get_password_hash, verify_password, create_access_token
from app.core.tenant import get_tenant_from_header
from app.dependencies import get_current_user

router = APIRouter()


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    data: UserRegister,
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
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
    db: AsyncSession = Depends(get_db),
    x_tenant_slug: str = Header(default="algeria"),
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

    return Token(
        access_token=access_token,
        token_type="bearer",
        expires_in=60 * 24,
    )


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user
