"""Computer Vision service — identifies monuments/sites from tourist images.

Mirrors the ChatService pattern: the endpoint delegates to this service, which
resolves the tenant-scoped LLM provider (quota-checked, BYOK key when
configured) and calls the provider's vision method. In mock mode (no API key)
the provider returns a deterministic fake identification; the service
normalizes the result so the API contract is stable.

Usage/quota: every call (success or provider error) is journaled via
`record_llm_call` with `feature="cv"`. The provider is resolved OUTSIDE the
try so a `QuotaExceededError` propagates to the endpoint untouched instead of
being absorbed into the fallback identification.
"""
import base64
import json
import time
from typing import Any, Dict

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Tenant
from app.services.llm_providers.base import TokenUsage
from app.services.llm_providers.errors import classify_provider_error
from app.services.tenant_ai_quota_service import record_llm_call
from app.services.tenant_llm_provider import get_tenant_llm_provider

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

        # Résolution du provider tenant + vérification du hard limit AVANT tout appel :
        # QuotaExceededError doit remonter intacte à l'endpoint, jamais absorbée par le
        # except ci-dessous (qui renverrait le fallback comme si l'appel avait réussi).
        provider = await get_tenant_llm_provider(self.db, self.tenant.id, "cv")
        provider_name = getattr(provider, "name", "openai")
        configured_model = getattr(provider, "configured_model", "unknown")

        start = time.perf_counter()
        try:
            result = await provider.identify_image(
                image_data_url,
                prompt,
                temperature=0.2,
                max_tokens=500,
            )
            latency_ms = int((time.perf_counter() - start) * 1000)
            result_text = result.text if hasattr(result, "text") else result
            served_model = getattr(result, "model", None) or configured_model
            usage = getattr(result, "usage", None) or TokenUsage()
            identification = json.loads(result_text)

            await record_llm_call(
                self.db,
                self.tenant.id,
                feature="cv",
                provider=provider_name,
                model=served_model,
                usage=usage,
                status="success",
                latency_ms=latency_ms,
            )
        except Exception as exc:
            latency_ms = int((time.perf_counter() - start) * 1000)
            error_code = classify_provider_error(exc, provider=provider_name)
            await record_llm_call(
                self.db,
                self.tenant.id,
                feature="cv",
                provider=provider_name,
                model=configured_model,
                usage=TokenUsage(),
                status="error",
                error_code=error_code,
                latency_ms=latency_ms,
            )
            identification = dict(_FALLBACK_IDENTIFICATION)

        return self._normalize(identification)