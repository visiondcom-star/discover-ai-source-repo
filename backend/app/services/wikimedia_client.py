"""Client minimal de l'API MediaWiki pour Wikivoyage et Wikipedia.

Sert au job de collecte : récupère le texte brut d'une page avec sa licence et
son attribution (CC BY-SA). Aucun appel LLM ici.
"""
import os
import re
from dataclasses import dataclass
from typing import Optional, Tuple
from urllib.parse import quote, unquote, urlsplit

import httpx

WIKIMEDIA_LICENSE = "CC BY-SA 4.0"
WIKI_PROJECTS = {"wikivoyage": "Wikivoyage", "wikipedia": "Wikipedia"}

# La politique Wikimedia exige un User-Agent identifiant l'application et un contact.
DEFAULT_USER_AGENT = (
    "DiscoverAI-ResearchCollector/0.1 "
    "(https://github.com/visiondcom-star/discover-ai-source-repo)"
)

_HOST_RE = re.compile(r"^([a-z]{2,3}(?:-[a-z]+)?)\.(wikivoyage|wikipedia)\.org$")
_LANG_RE = re.compile(r"^[a-z]{2,3}(?:-[a-z]+)?$")


class WikimediaError(Exception):
    """Erreur réseau ou de réponse lors d'un appel à l'API MediaWiki."""


@dataclass(frozen=True)
class WikiPage:
    project: str
    lang: str
    title: str
    url: str
    text: str
    license: str
    attribution: str


def parse_wiki_url(url: str) -> Optional[Tuple[str, str, str]]:
    """Décompose une URL `https://fr.wikivoyage.org/wiki/Kabylie` en
    (projet, langue, titre). Renvoie None si ce n'est pas une page Wikimedia."""
    parts = urlsplit((url or "").strip())
    match = _HOST_RE.match(parts.netloc.lower())
    if not match or not parts.path.startswith("/wiki/"):
        return None
    title = unquote(parts.path[len("/wiki/"):]).replace("_", " ").strip()
    if not title:
        return None
    return match.group(2), match.group(1), title


class WikimediaClient:
    """Utilisation : `async with WikimediaClient() as wiki: await wiki.fetch_page(...)`.

    `transport` permet d'injecter un `httpx.MockTransport` dans les tests.
    """

    def __init__(
        self,
        transport: Optional[httpx.AsyncBaseTransport] = None,
        timeout: float = 15.0,
        user_agent: Optional[str] = None,
    ):
        self._transport = transport
        self._timeout = timeout
        self._user_agent = user_agent or os.getenv("WIKIMEDIA_USER_AGENT", DEFAULT_USER_AGENT)
        self._http: Optional[httpx.AsyncClient] = None

    async def __aenter__(self) -> "WikimediaClient":
        self._http = httpx.AsyncClient(
            transport=self._transport,
            timeout=self._timeout,
            headers={"User-Agent": self._user_agent, "Accept": "application/json"},
            follow_redirects=True,
        )
        return self

    async def __aexit__(self, *exc) -> None:
        if self._http is not None:
            await self._http.aclose()
            self._http = None

    async def fetch_page(self, project: str, lang: str, title: str) -> Optional[WikiPage]:
        """Renvoie la page (texte brut) ou None si elle n'existe pas / est vide.

        Lève WikimediaError sur erreur HTTP ou réponse illisible.
        """
        if self._http is None:
            raise RuntimeError("WikimediaClient doit être utilisé via 'async with'.")
        if project not in WIKI_PROJECTS:
            raise ValueError(f"Projet Wikimedia inconnu : {project!r}")
        if not _LANG_RE.match(lang):
            raise ValueError(f"Code de langue invalide : {lang!r}")

        params = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "prop": "extracts|info",
            "explaintext": "1",
            "exsectionformat": "plain",
            "inprop": "url",
            "redirects": "1",
            "titles": title,
        }
        try:
            resp = await self._http.get(f"https://{lang}.{project}.org/w/api.php", params=params)
            resp.raise_for_status()
            payload = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise WikimediaError(f"{project}/{lang}/{title} : {exc}") from exc

        pages = (payload.get("query") or {}).get("pages") or []
        if not pages:
            return None
        page = pages[0]
        if page.get("missing") or page.get("invalid"):
            return None
        text = (page.get("extract") or "").strip()
        if not text:
            return None

        canonical = page.get("title") or title
        url = page.get("fullurl") or (
            f"https://{lang}.{project}.org/wiki/{quote(canonical.replace(' ', '_'))}"
        )
        attribution = (
            f"{canonical} — contributeurs de {WIKI_PROJECTS[project]} ({lang}), "
            f"{url}, {WIKIMEDIA_LICENSE}"
        )
        return WikiPage(
            project=project,
            lang=lang,
            title=canonical,
            url=url,
            text=text,
            license=WIKIMEDIA_LICENSE,
            attribution=attribution,
        )
