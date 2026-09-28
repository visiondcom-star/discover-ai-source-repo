import httpx
import pytest

from app.services.research_collection_service import build_targets, compute_content_hash
from app.services.wikimedia_client import (
    WIKIMEDIA_LICENSE,
    WikimediaClient,
    WikimediaError,
    parse_wiki_url,
)


def _client(handler):
    return WikimediaClient(transport=httpx.MockTransport(handler))


def test_parse_wiki_url():
    assert parse_wiki_url("https://fr.wikivoyage.org/wiki/Grande_Kabylie") == (
        "wikivoyage", "fr", "Grande Kabylie",
    )
    assert parse_wiki_url("https://en.wikipedia.org/wiki/Kabylia") == (
        "wikipedia", "en", "Kabylia",
    )
    assert parse_wiki_url("https://example.com/wiki/Kabylie") is None
    assert parse_wiki_url("https://fr.wikipedia.org/w/index.php?title=X") is None
    assert parse_wiki_url("") is None


async def test_fetch_page_ok_sets_license_and_attribution():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["host"] = request.url.host
        seen["ua"] = request.headers["user-agent"]
        seen["titles"] = request.url.params["titles"]
        return httpx.Response(200, json={"query": {"pages": [{
            "title": "Kabylie",
            "extract": "La Kabylie est une région montagneuse du nord de l'Algérie.",
            "fullurl": "https://fr.wikivoyage.org/wiki/Kabylie",
        }]}})

    async with _client(handler) as wiki:
        page = await wiki.fetch_page("wikivoyage", "fr", "Kabylie")

    assert seen["host"] == "fr.wikivoyage.org"
    assert "DiscoverAI" in seen["ua"]
    assert seen["titles"] == "Kabylie"
    assert page.license == WIKIMEDIA_LICENSE
    assert "Wikivoyage" in page.attribution and page.url in page.attribution
    assert page.text.startswith("La Kabylie")


async def test_fetch_page_missing_returns_none():
    def handler(request):
        return httpx.Response(200, json={"query": {"pages": [{"title": "X", "missing": True}]}})

    async with _client(handler) as wiki:
        assert await wiki.fetch_page("wikipedia", "fr", "X") is None


async def test_fetch_page_http_error_raises():
    async with _client(lambda r: httpx.Response(503)) as wiki:
        with pytest.raises(WikimediaError):
            await wiki.fetch_page("wikipedia", "fr", "Kabylie")


async def test_fetch_page_rejects_bad_lang():
    async with _client(lambda r: httpx.Response(200, json={})) as wiki:
        with pytest.raises(ValueError):
            await wiki.fetch_page("wikipedia", "fr.evil.com/", "Kabylie")


def test_build_targets_dedup_and_manual_pages():
    targets = build_targets(
        "Kabylie",
        ["fr", "en"],
        ["https://fr.wikivoyage.org/wiki/Kabylie", "https://fr.wikivoyage.org/wiki/Tizi_Ouzou", "https://x.org/y"],
    )
    assert ("wikivoyage", "fr", "Kabylie") in targets
    assert ("wikipedia", "en", "Kabylie") in targets
    assert ("wikivoyage", "fr", "Tizi Ouzou") in targets
    assert len(targets) == 5  # 4 (2 projets x 2 langues) + Tizi Ouzou, doublon Kabylie fusionné


def test_content_hash_normalization_matches_ingest_document():
    """Contrat partagé avec `_ingest_document` (endpoints/tenants.py:177) :
    `strip()` des extrémités uniquement — l'espacement interne est significatif.

    Si la collecte normalisait plus que l'ingestion par API (réduction des
    espaces, minuscules...), le même contenu produirait deux hashs différents,
    donc deux `destination_research_documents` pour un seul texte.
    """
    # Extrémités ignorées (comportement identique des deux côtés du chemin).
    assert compute_content_hash("  Kabylie, montagnes  ") == compute_content_hash(
        "Kabylie, montagnes"
    )
    # Espacement interne significatif : pas de normalisation cachée.
    assert compute_content_hash("a  b") != compute_content_hash("a b")
    assert compute_content_hash("a\nb") != compute_content_hash("a b")
    # sha256 hexdigest (64 caractères) — contrainte de la colonne content_hash.
    assert len(compute_content_hash("Kabylie")) == 64
