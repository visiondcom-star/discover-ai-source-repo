"""Application configuration with Pydantic Settings."""
from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache

# The insecure placeholder shipped as the SECRET_KEY default below. Kept as a
# named constant so the production startup guard and the default stay in sync.
INSECURE_DEFAULT_SECRET_KEY = "super-secret-key-change-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

    APP_NAME: str = "Discover AI"
    VERSION: str = "1.0.0"
    DEBUG: bool = False

    # Runtime environment: "development" (default) or "production".
    # When "production", insecure defaults are rejected at startup (see guard).
    ENV: str = "development"

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@db:5432/discoverai"

    # Redis
    REDIS_URL: str = "redis://redis:6379/0"

    # Security
    SECRET_KEY: str = INSECURE_DEFAULT_SECRET_KEY
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 1 day

    # LLM Provider
    LLM_PROVIDER: str = "mock"
    USE_PGVECTOR: bool = False

    # OpenAI
    OPENAI_API_KEY: str = ""
    OPENAI_MODEL: str = "gpt-4o"
    EMBEDDING_MODEL: str = "text-embedding-3-small"

    # Default tenant
    DEFAULT_TENANT_SLUG: str = "algeria"

    @model_validator(mode="after")
    def _reject_insecure_production_config(self) -> "Settings":
        """Fail fast when booting production with an unsafe SECRET_KEY.

        The application must never start in production while JWTs would be
        signed with the well-known repository default (or with nothing at
        all): anyone with access to the public source could forge tokens.
        """
        if self.ENV.strip().lower() == "production":
            if not self.SECRET_KEY or self.SECRET_KEY == INSECURE_DEFAULT_SECRET_KEY:
                raise ValueError(
                    "SECRET_KEY is not configured for production: refusing to "
                    "start. Set SECRET_KEY to a long random value when "
                    "ENV=production (e.g. `openssl rand -hex 32`)."
                )
        return self


@lru_cache()
def get_settings() -> Settings:
    return Settings()
