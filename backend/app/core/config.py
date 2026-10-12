"""App settings, read from environment variables (or a local .env file).

Every setting has a local-development default. In AWS, ECS overrides them
with environment variables: DB_HOST points at RDS, DB_PORT is 5432, and
DB_PASSWORD is injected from Secrets Manager. database_url() turns these
into the connection string SQLAlchemy uses.
"""

from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables / .env file."""

    APP_NAME: str = "SmallProject API"
    API_V1_PREFIX: str = "/api/v1"

    DB_HOST: str = "localhost"
    DB_PORT: int = 5433
    DB_USER: str = "postgres"
    DB_PASSWORD: str = "postgres"
    DB_NAME: str = "smallproject"

    CORS_ORIGINS: list[str] = ["http://localhost:5173"]

    model_config = SettingsConfigDict(env_file=".env")

    def database_url(self, db_name: str | None = None) -> str:
        # quote_plus: AWS-generated passwords can contain characters like # or : that break a URL.
        return (
            f"postgresql+psycopg://{self.DB_USER}:{quote_plus(self.DB_PASSWORD)}"
            f"@{self.DB_HOST}:{self.DB_PORT}/{db_name or self.DB_NAME}"
        )


settings = Settings()
