"""Runner du job de collecte automatique (étape « Recherche »).

Ne fait aucun appel LLM : il télécharge des pages Wikivoyage/Wikipedia et les
stocke dans `destination_research_documents` (status "raw"), avec licence et
attribution. Le pipeline d'extraction existant les consomme ensuite.

Cibles collectées :
  1. base universelle : le nom du territoire sur Wikivoyage et Wikipedia,
     dans les langues demandées (job.params["languages"], défaut fr + en) ;
  2. sources résolues du tenant (config pays surchargée par le tenant) de type
     "wiki" dont l'URL pointe vers une page Wikimedia (= pages ajoutées à la main).
Les autres types de sources (office_tourisme, guide...) sont ignorés ici : elles
relèveront du connecteur de sources officielles.

job.params reconnus : {"territory": "Kabylie", "languages": ["fr", "en"]}
"""
import hashlib
import logging
from datetime import datetime, timezone
from typing import List, Optional, Set, Tuple
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import DestinationResearchDocument, ResearchCollectionJob, Tenant
from app.services.research_source_service import resolve_sources
from app.services.wikimedia_client import (
    WIKI_PROJECTS,
    WikimediaClient,
    WikimediaError,
    parse_wiki_url,
)

logger = logging.getLogger(__name__)

DEFAULT_LANGUAGES = ["fr", "en"]
MIN_TEXT_LENGTH = 100  # en dessous : page vide / homonymie / ébauche inutilisable
MAX_ERRORS_KEPT = 5

Target = Tuple[str, str, str, bool]  # (projet, langue, titre, allow_fallback)


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def compute_content_hash(text: str) -> str:
    """sha256 hex de `text.strip()`.

    Identique à `_ingest_document` (tenants.py) : un même contenu ingéré par
    upload ou par collecte produit le même hash et n'est stocké qu'une fois.
    """
    return hashlib.sha256(text.strip().encode("utf-8")).hexdigest()


def build_targets(
    territory: Optional[str],
    languages: List[str],
    wiki_source_urls: List[str],
) -> List[Target]:
    targets: List[Target] = []
    seen: Set[Tuple[str, str, str]] = set()

    def add(project: str, lang: str, title: str, allow_fallback: bool) -> None:
        key = (project, lang, title.strip().lower())
        if key not in seen:
            seen.add(key)
            targets.append((project, lang, title.strip(), allow_fallback))

    if territory and territory.strip():
        for project in WIKI_PROJECTS:
            for lang in languages:
                add(project, lang, territory, allow_fallback=True)

    for url in wiki_source_urls:
        parsed = parse_wiki_url(url)
        if parsed:
            # Source ajoutée à la main par l'admin : titre exact voulu, jamais
            # de repli par recherche (l'admin a choisi cette page précise).
            add(*parsed, allow_fallback=False)
        else:
            logger.info("Source wiki ignorée (URL non Wikimedia) : %s", url)
    return targets


async def run_collection_job(job_id: UUID, client: Optional[WikimediaClient] = None) -> None:
    """Point d'entrée pour BackgroundTasks (même forme que `_run_research_pipeline`) :
    ouvre sa propre session DB, indépendante de celle de la requête HTTP qui l'a
    lancé (elle serait déjà fermée au moment où la tâche de fond s'exécute)."""
    from app.database import AsyncSessionLocal  # import local : évite un cycle au chargement du module

    async with AsyncSessionLocal() as session:
        await run_collection_job_with_session(session, job_id, client=client)


async def run_collection_job_with_session(
    db: AsyncSession,
    job_id: UUID,
    client: Optional[WikimediaClient] = None,
) -> None:
    """Cœur de la collecte, avec une session fournie par l'appelant.

    Utilisé directement par les tests (session de test déjà ouverte) ; en
    production, passe toujours par `run_collection_job` ci-dessus.
    Exécute le job : pending -> processing -> done | failed. Ne lève pas.
    """
    job = await db.get(ResearchCollectionJob, job_id)
    if job is None:
        logger.error("ResearchCollectionJob %s introuvable", job_id)
        return

    tenant_id = job.tenant_id
    params = dict(job.params or {})
    job.status = "processing"
    job.started_at = _now()
    await db.commit()

    fetched = new = duplicate = failed = 0
    errors: List[str] = []

    try:
        tenant = await db.get(Tenant, tenant_id)
        if tenant is None:
            raise RuntimeError(f"Tenant {tenant_id} introuvable")

        territory = params.get("territory") or getattr(tenant, "name", None)
        languages = params.get("languages") or DEFAULT_LANGUAGES
        sources = await resolve_sources(db, tenant)
        wiki_urls = [s.url for s in sources if s.source_type == "wiki"]
        targets = build_targets(territory, languages, wiki_urls)

        async with (client or WikimediaClient()) as wiki:
            for project, lang, title, allow_fallback in targets:
                try:
                    page = await wiki.fetch_page(project, lang, title)
                    if page is None and allow_fallback:
                        candidates = await wiki.search_title(project, lang, title)
                        for candidate in candidates:
                            if candidate.strip().lower() == title.strip().lower():
                                continue  # déjà tenté sous ce nom exact
                            page = await wiki.fetch_page(project, lang, candidate)
                            if page is not None:
                                logger.info(
                                    "Repli titre %s/%s : %r -> %r", project, lang, title, candidate
                                )
                                break
                except WikimediaError as exc:
                    failed += 1
                    errors.append(str(exc))
                    continue

                if page is None or len(page.text) < MIN_TEXT_LENGTH:
                    # Page absente (même après repli) ou inutilisable
                    failed += 1
                    errors.append(f"{project}/{lang}/{title} : page absente ou trop courte")
                    continue

                fetched += 1
                content_hash = compute_content_hash(page.text)
                already = await db.scalar(
                    select(DestinationResearchDocument.id).where(
                        DestinationResearchDocument.tenant_id == tenant_id,
                        DestinationResearchDocument.content_hash == content_hash,
                    )
                )
                if already:
                    duplicate += 1
                    continue

                try:
                    async with db.begin_nested():
                        db.add(
                            DestinationResearchDocument(
                                tenant_id=tenant_id,
                                source_type="wiki",
                                source_url=page.url[:500],
                                raw_text=page.text,
                                language=page.lang,
                                license=page.license,
                                attribution=page.attribution,
                                content_hash=content_hash,
                            )
                        )
                    await db.commit()
                    new += 1
                except IntegrityError:
                    # Course avec un autre run : la contrainte unique a joué
                    duplicate += 1

        status = "failed" if (fetched == 0 and failed > 0) else "done"
        error_message = "; ".join(errors[:MAX_ERRORS_KEPT]) or None
    except Exception as exc:  # noqa: BLE001 — le job doit toujours se terminer proprement
        logger.exception("Collecte %s en échec", job_id)
        await db.rollback()
        status = "failed"
        error_message = str(exc)[:1000]

    job = await db.get(ResearchCollectionJob, job_id)
    await db.refresh(job)
    job.status = status
    job.finished_at = _now()
    job.documents_fetched = fetched
    job.documents_new = new
    job.documents_duplicate = duplicate
    job.documents_failed = failed
    job.error_message = error_message
    await db.commit()
