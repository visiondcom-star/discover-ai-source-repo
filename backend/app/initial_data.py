"""Initialize demo data on first startup."""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Tenant, User, POI
from app.core.security import get_password_hash


async def init_db():
    async with AsyncSessionLocal() as session:
        await _create_demo_tenants(session)
        await _create_demo_users(session)
        await _create_demo_pois(session)
        await session.commit()


async def _create_demo_tenants(session: AsyncSession):
    result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
    if result.scalar_one_or_none():
        return

    algeria = Tenant(
        slug="algeria",
        name="Discover Algeria",
        default_language="fr",
        supported_languages=["fr", "ar", "en"],
        default_currency="DZD",
        primary_color="#006233",
        secondary_color="#FFFFFF",
        config={"rtl": False, "timezone": "Africa/Algiers"},
    )
    session.add(algeria)

    morocco = Tenant(
        slug="morocco",
        name="Discover Morocco",
        default_language="fr",
        supported_languages=["fr", "ar", "en"],
        default_currency="MAD",
        primary_color="#C1272D",
        secondary_color="#006233",
        config={"rtl": False, "timezone": "Africa/Casablanca"},
    )
    session.add(morocco)
    await session.flush()


async def _create_demo_users(session: AsyncSession):
    result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
    tenant = result.scalar_one_or_none()
    if not tenant:
        return

    result = await session.execute(select(User).where(User.email == "demo@algeria.travel"))
    if result.scalar_one_or_none():
        return

    demo_user = User(
        tenant_id=tenant.id,
        email="demo@algeria.travel",
        hashed_password=get_password_hash("demo1234"),
        full_name="Demo User",
        is_active=True,
        is_admin=False,
    )
    session.add(demo_user)

    admin_user = User(
        tenant_id=tenant.id,
        email="admin@algeria.travel",
        hashed_password=get_password_hash("admin1234"),
        full_name="Admin User",
        is_active=True,
        is_admin=True,
    )
    session.add(admin_user)
    await session.flush()


async def _create_demo_pois(session: AsyncSession):
    result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
    tenant = result.scalar_one_or_none()
    if not tenant:
        return

    result = await session.execute(select(POI).where(POI.tenant_id == tenant.id).limit(1))
    if result.scalar_one_or_none():
        return

    demo_pois = [
        {
            "slug": "casbah-dalger",
            "name": "Casbah d'Alger",
            "description": "La Casbah d'Alger est la médina fortifiée de la ville d'Alger, classée au patrimoine mondial de l'UNESCO. C'est un labyrinthe de ruelles étroites, de maisons traditionnelles et de palais ottomans.",
            "city": "Alger",
            "category": "historical",
            "duration_minutes": 120,
            "price_range": "free",
            "latitude": 36.7869,
            "longitude": 3.0601,
            "tags": ["unesco", "ottoman", "medina", "architecture"],
            "is_verified": True,
        },
        {
            "slug": "jardin-essai-hamma",
            "name": "Jardin d'Essai du Hamma",
            "description": "Un magnifique jardin botanique créé en 1832, abritant des milliers d'espèces végétales. Parfait pour une promenade relaxante au cœur d'Alger.",
            "city": "Alger",
            "category": "nature",
            "duration_minutes": 90,
            "price_range": "low",
            "latitude": 36.7489,
            "longitude": 3.0750,
            "tags": ["jardin", "botanique", "nature", "famille"],
            "is_verified": True,
        },
        {
            "slug": "ruines-tipaza",
            "name": "Ruines de Tipaza",
            "description": "Site archéologique romain exceptionnel situé en bord de mer, classé au patrimoine mondial de l'UNESCO. Théâtre, basiliques, nécropoles et musée.",
            "city": "Tipaza",
            "category": "historical",
            "duration_minutes": 120,
            "price_range": "low",
            "latitude": 36.5944,
            "longitude": 2.4431,
            "tags": ["unesco", "romain", "archéologie", "mer"],
            "is_verified": True,
        },
        {
            "slug": "ponts-constantine",
            "name": "Ponts de Constantine",
            "description": "Constantine, la ville des ponts suspendus, offre des vues spectaculaires sur le canyon du Rhummel. Le pont Sidi M'Cid est l'emblème de la ville.",
            "city": "Constantine",
            "category": "culture",
            "duration_minutes": 150,
            "price_range": "free",
            "latitude": 36.3650,
            "longitude": 6.6147,
            "tags": ["ponts", "canyon", "vue panoramique", "architecture"],
            "is_verified": True,
        },
        {
            "slug": "tassili-najjer",
            "name": "Tassili n'Ajjer",
            "description": "Vaste plateau du Sahara avec des gravures rupestres millénaires et des formations rocheuses spectaculaires. Classé au patrimoine mondial de l'UNESCO.",
            "city": "Djanet",
            "category": "adventure",
            "duration_minutes": 480,
            "price_range": "high",
            "latitude": 26.0,
            "longitude": 7.0,
            "tags": ["unesco", "sahara", "gravures", "aventure", "trekking"],
            "is_verified": True,
        },
        {
            "slug": "maqam-echahid",
            "name": "Maqam Echahid",
            "description": "Monument emblématique d'Alger, trois palmes de béton culminant à 92m, symbolisant l'indépendance de l'Algérie. Vue panoramique sur la baie d'Alger.",
            "city": "Alger",
            "category": "historical",
            "duration_minutes": 60,
            "price_range": "free",
            "latitude": 36.7458,
            "longitude": 3.0697,
            "tags": ["monument", "indépendance", "vue", "symbole"],
            "is_verified": True,
        },
        {
            "slug": "ruines-djemila",
            "name": "Ruines de Djemila",
            "description": "Site archéologique romain parmi les mieux conservés d'Afrique du Nord. Théâtre, temples, forums et maisons romaines. Classé UNESCO.",
            "city": "Sétif",
            "category": "historical",
            "duration_minutes": 180,
            "price_range": "low",
            "latitude": 36.3206,
            "longitude": 5.7361,
            "tags": ["unesco", "romain", "archéologie", "théâtre"],
            "is_verified": True,
        },
        {
            "slug": "vallee-mzab",
            "name": "Vallée du M'zab",
            "description": "Cinq ksour fortifiés dans un paysage désertique, exemple unique d'architecture ibadite. Classé au patrimoine mondial de l'UNESCO.",
            "city": "Ghardaia",
            "category": "culture",
            "duration_minutes": 240,
            "price_range": "medium",
            "latitude": 32.4833,
            "longitude": 3.6833,
            "tags": ["unesco", "ksar", "ibadite", "désert", "architecture"],
            "is_verified": True,
        },
    ]

    for poi_data in demo_pois:
        poi = POI(tenant_id=tenant.id, **poi_data)
        session.add(poi)
