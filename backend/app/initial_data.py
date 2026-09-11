"""Initialize demo data on first startup."""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Tenant, TenantCategory, User, POI, Promotion
from app.core.security import get_password_hash


async def init_db():
    async with AsyncSessionLocal() as session:
        await _create_demo_tenants(session)
        await _create_demo_categories(session)
        await _create_demo_users(session)
        await _create_demo_pois(session)
        await _create_demo_promotions(session)
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


async def _create_demo_categories(session: AsyncSession):
    result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
    tenant = result.scalar_one_or_none()
    if not tenant:
        return

    existing = await session.execute(
        select(TenantCategory).where(TenantCategory.tenant_id == tenant.id).limit(1)
    )
    if existing.scalar_one_or_none():
        return

    categories = [
        {
            "parent_family": "culture",
            "slug": "culture",
            "label": "Culture & Médinas",
            "icon_suggestion": "landmark",
            "display_order": 1,
            "description": "Casbahs, citadelles ottomanes, palais et patrimoine urbain.",
            "ai_generated": True,
        },
        {
            "parent_family": "history",
            "slug": "historical",
            "label": "Histoire & Antiquité",
            "icon_suggestion": "castle",
            "display_order": 2,
            "description": "Ruines romaines, cités numides et ensemble archéologique millénaire.",
            "ai_generated": True,
        },
        {
            "parent_family": "nature",
            "slug": "nature",
            "label": "Nature & Parcs",
            "icon_suggestion": "trees",
            "display_order": 3,
            "description": "Parcs nationaux, réserves de biosphère et vallées verdoyantes.",
            "ai_generated": True,
        },
        {
            "parent_family": "desert",
            "slug": "desert",
            "label": "Sahara & Oasis",
            "icon_suggestion": "sun",
            "display_order": 4,
            "description": "Dunes du Grand Erg, gravures rupestres du Tassili et oasis du Sud.",
            "ai_generated": True,
        },
        {
            "parent_family": "adventure",
            "slug": "adventure",
            "label": "Aventure & Trekking",
            "icon_suggestion": "mountain",
            "display_order": 5,
            "description": "Treks sahariens, escalade dans les massifs et randonnées en montagne.",
            "ai_generated": True,
        },
        {
            "parent_family": "food",
            "slug": "food",
            "label": "Gastronomie & Terroir",
            "icon_suggestion": "utensils",
            "display_order": 6,
            "description": "Saveurs ancestrales, couscous du terroir, dattes et pâtisseries fines.",
            "ai_generated": True,
        },
        {
            "parent_family": "beaches",
            "slug": "beaches",
            "label": "Plages & Littoral",
            "icon_suggestion": "palmtree",
            "display_order": 7,
            "description": "Corniches turquoise, criques préservées et stations balnéaires.",
            "ai_generated": True,
        },
        {
            "parent_family": "history",
            "slug": "monuments",
            "label": "Monuments & Sites",
            "icon_suggestion": "compass",
            "display_order": 8,
            "description": "Mémoriaux, ponts suspendus et édifices emblématiques.",
            "ai_generated": True,
        },
        {
            "parent_family": "culture",
            "slug": "crafts",
            "label": "Artisanat & Souks",
            "icon_suggestion": "shopping-bag",
            "display_order": 9,
            "description": "Dinanderie, poterie kabyle, tapis du M'Zab et souks artisanaux.",
            "ai_generated": True,
        },
        {
            "parent_family": "wellness",
            "slug": "thermal",
            "label": "Thermalisme & Eaux",
            "icon_suggestion": "waves",
            "display_order": 10,
            "description": "Sources thermales réputées, vertus thérapeutiques millénaires.",
            "ai_generated": True,
        },
        {
            "parent_family": "wellness",
            "slug": "wellness",
            "label": "Détente & Hammams",
            "icon_suggestion": "sparkles",
            "display_order": 11,
            "description": "Hammams traditionnels, rituels de relaxation et sérénité.",
            "ai_generated": True,
        },
        {
            "parent_family": None,
            "slug": "more",
            "label": "Toutes les activités",
            "icon_suggestion": "plus-circle",
            "display_order": 12,
            "description": "Exploration complète du catalogue des trésors d'Algérie.",
            "ai_generated": False,
        },
    ]

    for cat_data in categories:
        cat = TenantCategory(tenant_id=tenant.id, **cat_data)
        session.add(cat)
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
            "categories": ["historical", "culture", "monuments"],
            "experiences": ["visiter", "deguster", "photographier", "decouvrir"],
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
            "categories": ["nature", "wellness", "monuments"],
            "experiences": ["se_promener", "decouvrir", "se_detendre", "photographier"],
            "duration_minutes": 90,
            "price_range": "low",
            "latitude": 36.7489,
            "longitude": 3.0750,
            "tags": ["jardin", "botanique", "nature", "detente"],
            "is_verified": True,
        },
        {
            "slug": "ruines-tipaza",
            "name": "Ruines de Tipaza",
            "description": "Tipasa abrite l'un des plus vastes ensembles archéologiques romains d'Afrique du Nord, classé UNESCO depuis 1982 sur la rive algérienne de la Méditerranée. Le parc archéologique réunit le théâtre romain, l'amphithéâtre, le forum, les thermes de l'Ouest, la basilique judiciaire chrétienne et la nécropole qui s'étend vers le mont Chenoua, avec un musée présentant mosaïques et stèles puniques et romaines. Ancien port carthaginois puis colonie de l'empereur Claude, le site se visite en 2 à 3 heures en bord de mer, à 70 km à l'ouest d'Alger — prévoir chaussures confortables ; entrée payante sauf le premier dimanche du mois.",
            "city": "Tipaza",
            "categories": ["historical", "monuments", "beaches"],
            "experiences": ["visiter", "marcher", "decouvrir", "photographier"],
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
            "categories": ["monuments", "culture", "historical"],
            "experiences": ["visiter", "photographier", "admirer"],
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
            "categories": ["desert", "adventure", "nature", "historical"],
            "experiences": ["bivouaquer", "randonner", "photographier", "explorer"],
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
            "categories": ["monuments", "historical", "culture"],
            "experiences": ["visiter", "photographier", "admirer"],
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
            "categories": ["historical", "monuments", "culture"],
            "experiences": ["visiter", "marcher", "decouvrir", "explorer"],
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
            "categories": ["culture", "desert", "crafts", "historical"],
            "experiences": ["visiter", "decouvrir", "rencontrer", "admirer"],
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


async def _create_demo_promotions(session: AsyncSession):
    result = await session.execute(select(Tenant).where(Tenant.slug == "algeria"))
    tenant = result.scalar_one_or_none()
    if not tenant:
        return

    existing = await session.execute(
        select(Promotion).where(Promotion.tenant_id == tenant.id)
    )
    if existing.scalar_one_or_none():
        return

    promotion = Promotion(
        tenant_id=tenant.id,
        title="L'Algérie vous attend",
        subtitle="Des paysages grandioses, une histoire millénaire, une hospitalité unique.",
                # Aerial view of the Roman ruins at Tipaza, Algeria — photo by Rab
        # Rabah (@rabrabi) on Unsplash, used under the Unsplash License
        # (free for commercial use, no attribution required).
        # https://unsplash.com/fr/photos/qI94ozTxOFc
        image_url="https://images.unsplash.com/photo-1629989714683-9861709b7856?fm=jpg&q=80&w=1200&h=600&fit=crop&auto=format",
        cta_label="Découvrir",
        link_type="none",
        priority=10,
        is_active=True,
    )
    session.add(promotion)
