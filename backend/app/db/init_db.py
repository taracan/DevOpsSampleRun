from sqlalchemy import create_engine, text

from app.core.config import settings
from app.db.base import Base
from app.db.session import engine
from app.models import user  # noqa: F401  (registers the model with Base)


def create_database() -> None:
    """Step 2: create the PostgreSQL database (if missing) and all tables."""
    admin_engine = create_engine(settings.database_url("postgres"), isolation_level="AUTOCOMMIT")
    with admin_engine.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": settings.DB_NAME}
        ).scalar()
        if not exists:
            conn.execute(text(f'CREATE DATABASE "{settings.DB_NAME}"'))
    admin_engine.dispose()

    Base.metadata.create_all(bind=engine)
