"""Tests des endpoints de contexte live (app/api/v1/endpoints/context.py).

Attention : ce module ne contient aujourd'hui que des données simulées
(météo, prévisions, événements, notifications codés en dur ; la publication
d'événement et « tout marquer comme lu » ne persistent rien). Ces tests
verrouillent le CONTRAT de l'API (formes, validations, accès, filtres), pas des
valeurs métier : ils évitent volontairement les valeurs simulées, pour rester
valables quand un vrai fournisseur (météo, événements) sera branché.

Hypothèses à vérifier contre app/schemas.py :
- WeatherResponse.forecast est une liste de dictionnaires (day, temp, humidity...)
- ContextEventCreate : voir PUBLISH_PAYLOAD.
"""
import types
from datetime import datetime, timedelta

import pytest

BASE = "/api/v1/context"
WEATHER = f"{BASE}/weather"
FORECAST = f"{BASE}/forecast"
EVENTS = f"{BASE}/events"
NOTIFICATIONS = f"{BASE}/notifications"
READ_ALL = f"{BASE}/notifications/read-all"

BASE_HEADERS = {"X-Tenant-Slug": "test-tenant"}

PUBLISH_PAYLOAD = {
    "event_type": "road_closure",
    "title": "Route fermée pour travaux",
    "description": "Fermeture temporaire de la route côtière",
    "severity": "warning",
    "location": "Alger",
}


@pytest.fixture
def pick_random(monkeypatch):
    """Rend déterministes les valeurs aléatoires de context.py ('low' ou 'high')."""
    import app.api.v1.endpoints.context as context_module

    def _set(pick):
        low = pick == "low"
        fake = types.SimpleNamespace(
            randint=lambda a, b: a if low else b,
            choice=lambda seq: seq[0] if low else seq[-1],
        )
        monkeypatch.setattr(context_module, "random", fake)

    return _set


# ------------------------------------------- en-tête tenant (routes publiques)

PUBLIC_PATHS = [
    f"{WEATHER}?city=Alger",
    f"{FORECAST}?city=Alger",
    EVENTS,
]


@pytest.mark.parametrize("path", PUBLIC_PATHS)
async def test_public_routes_require_tenant_header(client, test_tenant, path):
    response = await client.get(path)
    assert response.status_code == 422


@pytest.mark.parametrize("path", PUBLIC_PATHS)
async def test_public_routes_reject_unknown_tenant(client, test_tenant, path):
    response = await client.get(path, headers={"X-Tenant-Slug": "does-not-exist"})
    assert response.status_code == 404


# ------------------------------------------------------------------ météo


async def test_weather_returns_conditions_and_three_day_forecast(client, test_tenant):
    response = await client.get(WEATHER, params={"city": "Alger"}, headers=BASE_HEADERS)
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["city"] == "Alger"
    for key in ("temperature", "condition", "humidity", "wind_speed"):
        assert key in data
    assert len(data["forecast"]) == 3


@pytest.mark.parametrize("pick, sign", [("low", -1), ("high", 1)])
async def test_weather_forecast_stays_within_bounds(
    client, test_tenant, pick_random, pick, sign
):
    pick_random(pick)
    response = await client.get(WEATHER, params={"city": "Alger"}, headers=BASE_HEADERS)
    assert response.status_code == 200, response.text
    data = response.json()

    # Écart maximal de ±3 °C et ±10 points d'humidité, humidité bornée à 20-90.
    expected_humidity = max(20, min(90, data["humidity"] + 10 * sign))
    for day in data["forecast"]:
        assert day["temp"] == data["temperature"] + 3 * sign
        assert day["humidity"] == expected_humidity


async def test_weather_unknown_city_falls_back_to_defaults(client, test_tenant):
    response = await client.get(
        WEATHER, params={"city": "Villeinconnue"}, headers=BASE_HEADERS
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["city"] == "Villeinconnue"
    assert isinstance(data["temperature"], (int, float))


async def test_weather_validates_city(client, test_tenant):
    too_short = await client.get(WEATHER, params={"city": "a"}, headers=BASE_HEADERS)
    missing = await client.get(WEATHER, headers=BASE_HEADERS)
    assert too_short.status_code == 422
    assert missing.status_code == 422


# ------------------------------------------------------------- prévisions


async def test_forecast_default_and_custom_days(client, test_tenant):
    default = await client.get(FORECAST, params={"city": "Alger"}, headers=BASE_HEADERS)
    longest = await client.get(
        FORECAST, params={"city": "Alger", "days": 14}, headers=BASE_HEADERS
    )
    assert default.status_code == 200, default.text
    assert len(default.json()["forecast"]) == 5
    assert len(longest.json()["forecast"]) == 14
    assert default.json()["city"] == "Alger"


@pytest.mark.parametrize("days", [0, 15])
async def test_forecast_validates_days(client, test_tenant, days):
    response = await client.get(
        FORECAST, params={"city": "Alger", "days": days}, headers=BASE_HEADERS
    )
    assert response.status_code == 422


async def test_forecast_entries_are_consistent(client, test_tenant):
    response = await client.get(
        FORECAST, params={"city": "Alger", "days": 7}, headers=BASE_HEADERS
    )
    entries = response.json()["forecast"]
    assert len(entries) == 7

    dates = [datetime.strptime(e["date"], "%Y-%m-%d") for e in entries]
    assert all(b - a == timedelta(days=1) for a, b in zip(dates, dates[1:]))
    for entry in entries:
        assert entry["temp_min"] < entry["temp_max"]
        assert 0 <= entry["precipitation_chance"] <= 100


# ------------------------------------------------------------- événements


async def test_events_city_filter_returns_matching_subset(client, test_tenant):
    everything = (await client.get(EVENTS, headers=BASE_HEADERS)).json()
    assert everything["total"] == len(everything["events"])
    assert everything["total"] > 0

    city = everything["events"][0]["city"]
    filtered = (
        await client.get(EVENTS, params={"city": city.upper()}, headers=BASE_HEADERS)
    ).json()
    assert 0 < filtered["total"] <= everything["total"]
    assert all(city.lower() in e["city"].lower() for e in filtered["events"])


async def test_events_unknown_city_returns_empty_list(client, test_tenant):
    response = await client.get(
        EVENTS, params={"city": "Villeinconnue"}, headers=BASE_HEADERS
    )
    assert response.status_code == 200
    assert response.json() == {"events": [], "total": 0}


async def test_publish_event_requires_auth(client, test_tenant):
    response = await client.post(EVENTS, headers=BASE_HEADERS, json=PUBLISH_PAYLOAD)
    assert response.status_code in (401, 403)


async def test_publish_event_by_admin_reports_publisher(
    client, admin_headers, test_admin
):
    response = await client.post(EVENTS, headers=admin_headers, json=PUBLISH_PAYLOAD)
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["status"] == "published"
    assert data["published_by"] == str(test_admin.id)


async def test_publish_event_validates_payload(client, admin_headers):
    response = await client.post(EVENTS, headers=admin_headers, json={})
    assert response.status_code == 422


# ---------------------------------------------------------- notifications


async def test_notifications_require_auth(client, test_tenant):
    response = await client.get(NOTIFICATIONS, headers=BASE_HEADERS)
    assert response.status_code in (401, 403)


async def test_notifications_shape_and_unread_count(client, auth_headers):
    response = await client.get(NOTIFICATIONS, headers=auth_headers)
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["notifications"], "au moins une notification attendue"
    assert data["unread_count"] == len([n for n in data["notifications"] if not n["read"]])

    only_unread = await client.get(
        NOTIFICATIONS, params={"unread_only": "true"}, headers=auth_headers
    )
    assert only_unread.status_code == 200
    assert all(not n["read"] for n in only_unread.json()["notifications"])


async def test_mark_all_read_requires_auth(client, test_tenant):
    response = await client.post(READ_ALL, headers=BASE_HEADERS)
    assert response.status_code in (401, 403)


async def test_mark_all_read_returns_a_count(client, auth_headers):
    response = await client.post(READ_ALL, headers=auth_headers)
    assert response.status_code == 200, response.text
    assert isinstance(response.json()["marked_as_read"], int)
