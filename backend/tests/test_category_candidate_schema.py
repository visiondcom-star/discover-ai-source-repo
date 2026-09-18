import pytest
from pydantic import ValidationError
from app.schemas import CategoryCandidate
from app.constants import PARENT_FAMILIES


def test_valid_candidate_accepted():
    candidate = CategoryCandidate.model_validate(
        {
            "label": "Randonnée en montagne",
            "description": "Sentiers de randonnée dans les massifs environnants.",
            "parent_level1_id": "adventure",
            "mapping_confidence": 0.95,
            "category_confidence": 0.90,
            "source_document_ids": ["11111111-1111-1111-1111-111111111111"],
        },
        context={"level1_ids": PARENT_FAMILIES},
    )
    assert candidate.parent_level1_id == "adventure"


def test_unknown_parent_level1_id_rejected():
    with pytest.raises(ValidationError):
        CategoryCandidate.model_validate(
            {
                "label": "Foot en salle",
                "description": "Terrains de foot en salle pour groupes.",
                "parent_level1_id": "sports",
                "mapping_confidence": 0.8,
                "category_confidence": 0.8,
                "source_document_ids": ["11111111-1111-1111-1111-111111111111"],
            },
            context={"level1_ids": PARENT_FAMILIES},
        )


def test_null_parent_level1_id_accepted():
    candidate = CategoryCandidate.model_validate(
        {
            "label": "Marché artisanal",
            "description": "Marché hebdomadaire d'artisanat local.",
            "parent_level1_id": None,
            "mapping_confidence": 0.3,
            "category_confidence": 0.85,
            "source_document_ids": ["11111111-1111-1111-1111-111111111111"],
        },
        context={"level1_ids": PARENT_FAMILIES},
    )
    assert candidate.parent_level1_id is None


def test_empty_source_document_ids_rejected():
    with pytest.raises(ValidationError):
        CategoryCandidate.model_validate(
            {
                "label": "Test",
                "description": "Description suffisamment longue pour passer.",
                "parent_level1_id": "culture",
                "mapping_confidence": 0.9,
                "category_confidence": 0.9,
                "source_document_ids": [],
            },
            context={"level1_ids": PARENT_FAMILIES},
        )
