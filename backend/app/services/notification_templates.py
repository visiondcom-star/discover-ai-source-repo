"""Localized notification templates (FR and EN).

Templates are indexed by notification type and locale.
If a requested locale has no template, it falls back to 'en'.
"""
from typing import Any, Dict, Optional, Tuple

NOTIFICATION_TEMPLATES: Dict[str, Dict[str, Dict[str, str]]] = {
    "booking_request_received": {
        "fr": {
            "title": "Nouvelle demande de réservation",
            "message": "Une nouvelle demande de réservation a été reçue pour {poi_name}.",
        },
        "en": {
            "title": "New booking request received",
            "message": "A new booking request has been received for {poi_name}.",
        },
    },
    "booking_confirmed": {
        "fr": {
            "title": "Réservation confirmée",
            "message": "Votre réservation pour {poi_name} a été confirmée.",
        },
        "en": {
            "title": "Booking confirmed",
            "message": "Your booking for {poi_name} has been confirmed.",
        },
    },
    "booking_declined": {
        "fr": {
            "title": "Réservation refusée",
            "message": "Votre réservation pour {poi_name} n'a pas pu être acceptée.",
        },
        "en": {
            "title": "Booking declined",
            "message": "Your booking for {poi_name} could not be accepted.",
        },
    },
    "booking_expired": {
        "fr": {
            "title": "Demande de réservation expirée",
            "message": "La demande de réservation pour {poi_name} a expiré sans réponse.",
        },
        "en": {
            "title": "Booking request expired",
            "message": "The booking request for {poi_name} has expired without response.",
        },
    },
}


def render_notification(
    type_: str,
    locale: str,
    payload: Optional[Dict[str, Any]] = None,
) -> Tuple[str, str]:
    """Render localized (title, message) for a notification type and locale.

    Falls back to 'en' if the locale is not available.
    Substitutes any placeholder values found in payload with graceful defaults.
    """
    templates_for_type = NOTIFICATION_TEMPLATES.get(type_)
    if not templates_for_type:
        title = type_.replace("_", " ").capitalize()
        message = (payload or {}).get("message", "")
        return title, message

    # Locale fallback to 'en'
    loc = (locale or "en").strip().lower()
    tmpl = templates_for_type.get(loc) or templates_for_type.get("en")
    if not tmpl:
        # Ultimate fallback
        tmpl = next(iter(templates_for_type.values()))

    default_poi_name = "votre destination" if loc == "fr" else "your destination"
    poi_name = (payload or {}).get("poi_name") or default_poi_name

    params = {
        "poi_name": poi_name,
        **(payload or {}),
    }
    params["poi_name"] = poi_name

    try:
        title = tmpl["title"].format(**params)
    except Exception:
        title = tmpl["title"]

    try:
        message = tmpl["message"].format(**params)
    except Exception:
        message = tmpl["message"]

    return title, message
