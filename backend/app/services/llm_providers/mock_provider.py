"""Deterministischer Mock-Provider — kein externer API-Call, für Dev/Tests ohne Kosten."""
from typing import Dict, List

from app.services.llm_providers.base import LLMProvider


class MockProvider(LLMProvider):
    async def complete(
        self,
        messages: List[Dict[str, str]],
        temperature: float = 0.7,
        max_tokens: int = 800,
    ) -> str:
        user_message = ""
        for m in reversed(messages):
            if m.get("role") == "user":
                user_message = m.get("content", "")
                break

        msg_lower = user_message.lower()
        if "casbah" in msg_lower or "alger" in msg_lower:
            return "La Casbah d'Alger est un site UNESCO incontournable avec ses ruelles étroites, ses palais ottomans et sa vue panoramique sur la baie. Je recommande une visite guidée de 2-3 heures."
        elif "tipaza" in msg_lower:
            return "Les ruines romaines de Tipaza sont magnifiques, situées en bord de mer. C'est un site UNESCO qui mérite une demi-journée. N'oubliez pas le musée sur place !"
        elif "constantine" in msg_lower:
            return "Constantine, la ville des ponts suspendus, offre des vues spectaculaires sur le canyon du Rhummel. Le pont Sidi M'Cid est emblématique."
        elif "manger" in msg_lower or "restaurant" in msg_lower or "cuisine" in msg_lower:
            return "La cuisine algérienne est riche et variée ! Essayez le couscous, le chorba, les brick à l'œuf, et le méchoui. Chaque région a ses spécialités."
        elif "itinéraire" in msg_lower or "voyage" in msg_lower or "plan" in msg_lower:
            return "Je peux vous aider à planifier un itinéraire personnalisé ! Dites-moi combien de jours vous avez, votre budget, et vos centres d'intérêt (culture, nature, aventure...)."
        else:
            return "Merci pour votre question ! Je suis votre guide touristique local, je suis là pour vous aider. Pourriez-vous me donner plus de détails sur ce que vous cherchez ?"

    async def embed(self, text: str) -> List[float]:
        """Deterministic fake embedding — hash-based, no network call, 1536 dims to match text-embedding-3-small."""
        import hashlib
        h = hashlib.sha256(text.encode()).digest()
        # Répète le hash pour remplir 1536 dimensions, normalisé entre -1 et 1
        raw = (h * (1536 // len(h) + 1))[:1536]
        return [(b - 128) / 128.0 for b in raw]
