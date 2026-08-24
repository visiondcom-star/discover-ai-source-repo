"""Production startup guard: ENV=production must reject insecure SECRET_KEY.

The application refuses to boot in production when SECRET_KEY is missing,
empty, or still set to the well-known repository default. These tests pin
that behaviour at the Settings level (the earliest possible failure point).
"""
import pytest
from pydantic import ValidationError

from app.config import INSECURE_DEFAULT_SECRET_KEY, Settings


def _settings_env(monkeypatch, secret):
    monkeypatch.setenv("ENV", "production")
    if secret is None:
        monkeypatch.delenv("SECRET_KEY", raising=False)
    else:
        monkeypatch.setenv("SECRET_KEY", secret)
    # _env_file=None: ignore any local .env so only these env vars matter.
    return Settings(_env_file=None)


def test_production_rejects_default_secret_key(monkeypatch):
    with pytest.raises(ValidationError, match="SECRET_KEY"):
        _settings_env(monkeypatch, INSECURE_DEFAULT_SECRET_KEY)


def test_production_rejects_empty_secret_key(monkeypatch):
    with pytest.raises(ValidationError, match="SECRET_KEY"):
        _settings_env(monkeypatch, "")


def test_production_rejects_missing_secret_key(monkeypatch):
    with pytest.raises(ValidationError, match="SECRET_KEY"):
        _settings_env(monkeypatch, None)


def test_production_accepts_strong_secret_key(monkeypatch):
    settings = _settings_env(monkeypatch, "a" * 64)
    assert settings.SECRET_KEY == "a" * 64
    assert settings.ENV == "production"


def test_development_still_boots_with_default_secret_key(monkeypatch):
    """Regression guard: dev/test workflows keep working unchanged."""
    monkeypatch.delenv("ENV", raising=False)
    monkeypatch.delenv("SECRET_KEY", raising=False)
    settings = Settings(_env_file=None)
    assert settings.SECRET_KEY == INSECURE_DEFAULT_SECRET_KEY