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
            "description": "Tipasa abrite l'un des plus vastes ensembles archéologiques romains d'Afrique du Nord, classé UNESCO depuis 1982 sur la rive algérienne de la Méditerranée. Le parc archéologique réunit le théâtre romain, l'amphithéâtre, le forum, les thermes de l'Ouest, la basilique judiciaire chrétienne et la nécropole qui s'étend vers le mont Chenoua, avec un musée présentant mosaïques et stèles puniques et romaines. Ancien port carthaginois puis colonie de l'empereur Claude, le site se visite en 2 à 3 heures en bord de mer, à 70 km à l'ouest d'Alger — prévoir chaussures confortables ; entrée payante sauf le premier dimanche du mois.",
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
            "description": "Constantine, la « ville des ponts suspendus », est construite à cheval sur les gorges profondes de 175 m du Rhummel. Sept ouvrages relient les deux rives, dont le célèbre pont Sidi M'Cid (1912, 175 m de hauteur), le pont Sidi Rached et ses 27 arches, et la passerelle Mellah Slimane. Ne pas manquer le Palais du Bey et ses jardins andalous, la mosquée Emir Abdelkader, le musée national Cirta et les panoramas sur le canyon au lever du jour. Capitale de l'Orient algérien, elle a été désignée capitale de la culture arabe en 2015.",
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
            "description": "Le parc culturel du Tassili n'Ajjer, classé au patrimoine mondial de l'UNESCO (mixte, nature et culture), couvre 72 000 km² de plateau gréseux au cœur du Sahara algérien, à la frontière libyenne et nigérienne. On y recense plus de 15 000 gravures et peintures rupestres vieilles de 10 000 ans (bovidienne, étage des chars...), témoins d'un Sahara alors verdoyant, ainsi que des forêts relictuelles de cyprès de Duprez — arbres millénaires uniques au monde. Point de départ : Djanet, accessible en avion depuis Alger ; excursions 4x4 et trekking de plusieurs jours avec guide obligatoire, bivouacs sous les étoiles, meilleure saison d'octobre à avril.",
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
            "description": "Djémila (Cuicul), classée au patrimoine mondial de l'UNESCO depuis 1982, est la ville romaine la mieux conservée d'Afrique du Nord. Fondée sous Trajan au 1er siècle sur un éperon rocheux à 900 m d'altitude, elle conserve son forum, son capitole, ses temples de Septime Sévère et de Vénus Genitrix, un théâtre pouvant accueillir 3 000 spectateurs, des thermes, l'arc de Caracalla et de somptueuses maisons à mosaïques ; le musée de Djémila expose parmi les plus riches collections de mosaïques romaines au monde. Site ouvert toute l'année, à 50 km de Sétif ; visiter tôt le matin en été.",
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
