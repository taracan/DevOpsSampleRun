"""Is this database usable? `python -m app.db.check` (exit 0 = yes, 1 = no).

Used by the restore drill (.github/workflows/restore-drill.yml): after a
snapshot of production is restored to a temporary database, this runs as a
one-off ECS task pointed at that copy (DB_HOST overridden). It proves the
backup can actually be read, not just that a snapshot exists.

It checks, and prints:
  revision  the Alembic version the database is at (alembic_version table)
  head      the newest migration in this image (migrations/versions/)
  users     how many rows the users table has

and fails (exit 1) if the database can't be reached, the revision isn't the
newest one, or the users table is empty (a production copy always has
users; an empty one means the restore lost the data).
"""

import sys

from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, text

from app.core.config import settings
from app.db.migrate import alembic_config


def check(db_name: str | None = None) -> bool:
    head = ScriptDirectory.from_config(alembic_config(db_name)).get_current_head()
    engine = create_engine(settings.database_url(db_name))
    try:
        with engine.connect() as conn:
            revision = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
            users = conn.execute(text("SELECT count(*) FROM users")).scalar()
    except Exception as exc:
        print(f"FAIL: cannot read the database ({type(exc).__name__}: {exc})")
        return False
    finally:
        engine.dispose()

    print(f"revision={revision} head={head} users={users}")
    if revision != head:
        print("FAIL: the database is not at the newest migration")
        return False
    if not users:
        print("FAIL: the users table is empty")
        return False
    print("OK: the database is readable, up to date, and has data")
    return True


if __name__ == "__main__":
    sys.exit(0 if check() else 1)
