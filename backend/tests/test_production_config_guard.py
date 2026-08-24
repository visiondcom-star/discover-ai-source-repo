"""Production startup guard: ENV=production must reject insecure settings.

Two failure classes are pinned here at the Settings level (the earliest
possible failure point):
- SECRET_KEY missing, empty, or still set to the well-known repository default;
- CORS_ORIGINS unset or containing the wildcard "*" (browsers would let any
  origin read authenticated API responses).
"""
import pytest
from pydantic import ValidationError

from app.config import INSECURE_DEFAULT_SECRET_KEY, Settings

SAFE_CORS = "https://app.example.com,https://admin.example.com"


def _settings_env(monkeypatch, secret, cors=SAFE_CORS):
    monkeypatch.setenv("ENV", "production")
    if secret is None:
        monkeypatch.delenv("SECRET_KEY", raising=False)
    else:
        monkeypatch.setenv("SECRET_KEY", secret)
    if cors is None:
        monkeypatch.delenv("CORS_ORIGINS", raising=False)
    else:
        monkeypatch.setenv("CORS_ORIGINS", cors)
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


def test_production_rejects_missing_cors_origins(monkeypatch):
    """CORS_ORIGINS is mandatory in production (no implicit fallback)."""
    with pytest.raises(ValidationError, match="CORS_ORIGINS"):
        _settings_env(monkeypatch, "a" * 64, cors=None)


def test_production_rejects_empty_cors_origins(monkeypatch):
    with pytest.raises(ValidationError, match="CORS_ORIGINS"):
        _settings_env(monkeypatch, "a" * 64, cors="")


def test_production_rejects_wildcard_cors_origin(monkeypatch):
    with pytest.raises(ValidationError, match="CORS_ORIGINS"):
        _settings_env(monkeypatch, "a" * 64, cors="*")


def test_production_rejects_wildcard_hidden_among_origins(monkeypatch):
    """A wildcard smuggled into an otherwise explicit list must fail too."""
    with pytest.raises(ValidationError, match="wildcard"):
        _settings_env(monkeypatch, "a" * 64, cors=f"{SAFE_CORS}, *")


def test_production_accepts_explicit_cors_origins(monkeypatch):
    settings = _settings_env(monkeypatch, "a" * 64)
    assert settings.cors_origins_list == [
        "https://app.example.com",
        "https://admin.example.com",
    ]


def test_development_still_boots_with_defaults(monkeypatch):
    """Regression guard: dev/test workflows keep working unchanged."""
    monkeypatch.delenv("ENV", raising=False)
    monkeypatch.delenv("SECRET_KEY", raising=False)
    monkeypatch.delenv("CORS_ORIGINS", raising=False)
    settings = Settings(_env_file=None)
    assert settings.SECRET_KEY == INSECURE_DEFAULT_SECRET_KEY
    assert settings.cors_origins_list == ["*"]