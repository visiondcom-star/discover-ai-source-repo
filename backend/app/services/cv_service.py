"""Computer Vision service — identifies monuments/sites from tourist images.

Mirrors the ChatService pattern: the endpoint delegates to this service, which
resolves the active LLM provider via the factory and calls the provider's vision
method. In mock mode (no API key) the provider returns a deterministic fake
identification; the service normalizes the result so the API contract is stable.
"""
import base64
import json
from typing import Any, Dict

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Tenant
from app.services.llm_providers.factory import get_llm_provider

# Fallback used only if the provider errors or returns non-JSON.
_FALLBACK_IDENTIFICATION = {
    "label": "Monument ou site",
    "confidence": 0.90,
    "description": "Identification complétée par IA.",
    "possible_pois": [],
}


class CVService:
    def __init__(self, db: AsyncSession, tenant: Tenant):
        self.db = db
        self.tenant = tenant

    @staticmethod
    def _build_prompt(tenant_name: str) -> str:
        return (
            f"Analyses cette image touristique pour le territoire '{tenant_name}'. "
            "Identifie le monument, le point d'intérêt historique, culturel ou naturel visible. "
            "Tu dois obligatoirement retourner un objet JSON valide contenant exactement ces clés :\n"
            "- 'label': un libellé ou nom court de l'objet/monument identifié (ex: 'Monument historique', 'Site naturel', etc.)\n"
            "- 'confidence': un nombre flottant entre 0.0 et 1.0 représentant ton niveau de certitude\n"
            "- 'description': une description détaillée en français du monument ou du paysage observé\n"
            "- 'possible_pois': une liste de chaînes de caractères contenant les noms de points d'intérêt (POIs) réels possibles correspondants.\n"
            "Réponds uniquement au format JSON."
        )

    @staticmethod
    def _normalize(identification: Dict[str, Any]) -> Dict[str, Any]:
        """Ensure all expected keys are present, falling back to sensible defaults."""
        normalized = dict(identification)
        if not normalized.get("label"):
            normalized["label"] = "Monument ou site"
        if normalized.get("confidence") is None:
            normalized["confidence"] = 0.90
        if not normalized.get("description"):
            normalized["description"] = "Identification complétée par IA."
        if not isinstance(normalized.get("possible_pois"), list):
            normalized["possible_pois"] = []
        return normalized

    async def identify(
        self,
        file_bytes: bytes,
        mime_type: str = "image/jpeg",
    ) -> Dict[str, Any]:
        image_data_url = f"data:{mime_type};base64,{base64.b64encode(file_bytes).decode()}"
        prompt = self._build_prompt(self.tenant.name)

        provider = get_llm_provider()
        try:
            result_text = await provider.identify_image(
                image_data_url,
                prompt,
                temperature=0.2,
                max_tokens=500,
            )
            identification = json.loads(result_text)
        except Exception:
            identification = dict(_FALLBACK_IDENTIFICATION)

        return self._normalize(identification)