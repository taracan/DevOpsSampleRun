"""Alembic migrations: they run, they undo, they adopt old databases, and they
match the models.

These tests use their own database, smallproject_migrations_test, dropped and
re-created for each test, so they never disturb the main test database.

  upgrade/downgrade  every migration can be applied, undone, and re-applied
  adoption           a database made the old way (create_all, no Alembic)
                     is stamped at the baseline, and its data is kept;
                     this is exactly what happens to production once
  models match       after all migrations, the database has the same
                     tables, columns and indexes as app/models/ (Alembic's
                     autogenerate finds nothing to add), so nobody forgets
                     to write a migration for a model change
"""

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect, text

from app.core.config import settings
from app.db.base import Base
from app.db.migrate import BASELINE, alembic_config, migrate
from app.models import user  # noqa: F401  (registers the model with Base)

DB = "smallproject_migrations_test"


@pytest.fixture
def fresh_db():
    """An empty database named DB (dropped and re-created)."""
    admin = create_engine(settings.database_url("postgres"), isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{DB}" WITH (FORCE)'))
        conn.execute(text(f'CREATE DATABASE "{DB}"'))
    admin.dispose()
    engine = create_engine(settings.database_url(DB))
    yield engine
    engine.dispose()


def tables(engine):
    return set(inspect(engine).get_table_names())


def test_upgrade_downgrade_upgrade(fresh_db):
    migrate(DB)
    assert {"users", "alembic_version"} <= tables(fresh_db)

    command.downgrade(alembic_config(DB), "base")
    assert "users" not in tables(fresh_db)

    command.upgrade(alembic_config(DB), "head")
    assert "users" in tables(fresh_db)


def test_existing_database_is_adopted_and_keeps_its_data(fresh_db):
    # The old way: tables made by the app itself, no Alembic bookkeeping.
    Base.metadata.create_all(fresh_db)
    with fresh_db.begin() as conn:
        conn.execute(
            text("INSERT INTO users (name, email, password_hash) VALUES ('Old', 'old@x.io', 'h')")
        )

    migrate(DB)

    with fresh_db.connect() as conn:
        assert conn.execute(text("SELECT version_num FROM alembic_version")).scalar() == BASELINE
        assert conn.execute(text("SELECT email FROM users")).scalar() == "old@x.io"


def test_models_match_migrations(fresh_db):
    migrate(DB)

    with fresh_db.connect() as conn:
        differences = compare_metadata(MigrationContext.configure(conn), Base.metadata)

    assert differences == []
