"""Bring the database schema up to date: `python -m app.db.migrate`.

The one entry point for database changes, used in three places:
  - your laptop, after `docker compose up -d` (and after pulling new code);
  - the tests (tests/conftest.py), so every test run also runs the
    migrations against a real Postgres;
  - every backend deploy: .github/workflows/deploy.yml starts the backend
    image as a one-off ECS task with this command, BEFORE the new version
    goes live. If it fails, the deploy stops and the old version keeps
    running.

What it does, in order:
  1. Creates the database if it doesn't exist yet (a fresh laptop).
  2. Adopts a database made before Alembic, once: if the users table exists
     but Alembic's bookkeeping table (alembic_version) doesn't, it marks the
     database as already at the baseline (0001) without running it. That's
     how production starts using Alembic without touching its data.
  3. Runs every migration not yet applied (`alembic upgrade head`).

It never runs at app start-up: with several tasks starting at once, they
would race each other.
"""

import logging
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

from app.core.config import settings

logger = logging.getLogger("app.db.migrate")

BACKEND_DIR = Path(__file__).resolve().parents[2]  # backend/ (or /app in the image)
BASELINE = "0001"


def alembic_config(db_name: str | None = None) -> Config:
    """Alembic settings, pointed at the given database (default: DB_NAME)."""
    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.attributes["url"] = settings.database_url(db_name)
    return cfg


def ensure_database(db_name: str) -> None:
    """Create the database if it's missing (connects to the admin DB 'postgres')."""
    admin = create_engine(settings.database_url("postgres"), isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": db_name}
        ).scalar()
        if not exists:
            conn.execute(text(f'CREATE DATABASE "{db_name}"'))
            logger.info("Created database %s", db_name)
    admin.dispose()


def adopt_existing_database(cfg: Config, db_name: str) -> None:
    """Mark a pre-Alembic database (users table, no alembic_version) as at the baseline."""
    engine = create_engine(settings.database_url(db_name))
    tables = set(inspect(engine).get_table_names())
    engine.dispose()
    if "users" in tables and "alembic_version" not in tables:
        command.stamp(cfg, BASELINE)
        logger.info("Existing database adopted: stamped at baseline %s", BASELINE)


def migrate(db_name: str | None = None) -> None:
    name = db_name or settings.DB_NAME
    ensure_database(name)
    cfg = alembic_config(name)
    adopt_existing_database(cfg, name)
    command.upgrade(cfg, "head")
    logger.info("Database %s is up to date", name)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    migrate()
