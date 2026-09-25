"""Tests du modèle TenantAIConfig qui ne nécessitent pas de base de données."""
import uuid

import pytest

from app.models import TENANT_CONFIGURABLE_FEATURES, TenantAIConfig


def test_models_accepts_configurable_features():
    cfg = TenantAIConfig(tenant_id=uuid.uuid4(), models={"chat": "m1", "research": "m2"})
    assert cfg.models == {"chat": "m1", "research": "m2"}


def test_embeddings_is_not_tenant_configurable():
    assert "embeddings" not in TENANT_CONFIGURABLE_FEATURES
    with pytest.raises(ValueError):
        TenantAIConfig(tenant_id=uuid.uuid4(), models={"embeddings": "text-embedding-x"})


def test_unknown_feature_rejected():
    with pytest.raises(ValueError):
        TenantAIConfig(tenant_id=uuid.uuid4(), models={"nimporte_quoi": "m"})


def test_none_models_becomes_empty_dict():
    cfg = TenantAIConfig(tenant_id=uuid.uuid4(), models=None)
    assert cfg.models == {}
