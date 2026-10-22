"""Alembic environment: how migrations connect to the database.

Alembic runs this file every time it migrates. It:
  - takes the database address from the app's settings (app/core/config.py,
    DB_* environment variables), or from config.attributes["url"] when
    app/db/migrate.py passes one in (tests use that to pick a database);
  - loads the app's models (app/models/) into Base.metadata, so
    `alembic revision --autogenerate` can compare models and database;
  - runs the pending migration scripts in migrations/versions/.

The URL is passed through config.attributes, not alembic.ini, because
passwords can contain "%" characters that ini files would misread.
"""

from alembic import context
from sqlalchemy import create_engine, pool

from app.core.config import settings
from app.db.base import Base
from app.models import user  # noqa: F401  (registers the model with Base)

config = context.config
target_metadata = Base.metadata
url = config.attributes.get("url") or settings.database_url()


def run_migrations_offline() -> None:
    """Print the SQL instead of running it (`alembic upgrade head --sql`)."""
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Connect and run the migrations, all in one transaction."""
    engine = create_engine(url, poolclass=pool.NullPool)
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
