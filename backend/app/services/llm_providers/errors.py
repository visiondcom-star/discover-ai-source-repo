"""Classification des erreurs provider en catégories stables (``AI_CALL_STATUSES``).

Une seule table de correspondance pour tout le projet : le Provider Health Check
(`tenant_ai_config_service`) et le journal d'usage (`tenant_ai_quota_service`) doivent parler
le même vocabulaire, sinon les rapports d'usage deviennent incomparables.

Le texte brut de l'erreur n'est jamais renvoyé ni journalisé : celui d'un provider peut
contenir un fragment de la clé API rejetée.
"""
from __future__ import annotations

# Catégories volontairement non utilisées aujourd'hui, faute de source fiable pour les
# distinguer : "rate_limited" (429 classé "quota_exceeded", aligné sur le health check),
# "timeout" (un timeout de connexion est un "network_error"), "cancelled" (aucune annulation
# explicite n'est propagée par les clients actuels).


def classify_provider_error(exc: BaseException, provider: str = "openai") -> str:
    """Catégorie stable pour une exception levée pendant un appel provider.

    ``unknown_error`` sert de repli : une nouvelle exception du SDK ne doit jamais introduire
    un statut inconnu dans le journal d'usage.

    L'ordre des tests est significatif : les erreurs HTTP du SDK héritent de ``APIStatusError``,
    donc les cas les plus spécifiques passent en premier.
    """
    if provider == "openai":
        import openai  # import paresseux : seul le provider openai a besoin du SDK ici

        if isinstance(exc, openai.AuthenticationError):
            return "invalid_api_key"
        if isinstance(exc, openai.PermissionDeniedError):
            return "permission_denied"
        if isinstance(exc, openai.NotFoundError):
            return "model_unavailable"
        if isinstance(exc, openai.RateLimitError):
            return "quota_exceeded"
        if isinstance(exc, (openai.APIConnectionError, openai.APITimeoutError)):
            return "network_error"
        if isinstance(exc, openai.APIStatusError):
            return "provider_error"
    return "unknown_error"
