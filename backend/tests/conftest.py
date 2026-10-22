"""Shared pytest fixtures: the app, running against a real PostgreSQL.

The tests use their own database, smallproject_test, so they never touch
the local dev data in smallproject. DB_NAME has to be set before the app
is imported, because app/db/session.py builds its engine at import time.
The other DB_* settings come from the environment as usual: locally, the
docker compose Postgres on port 5433; in CI, a Postgres service on 5432.

  client  a TestClient for the app. Before it starts, the test database
          is created and migrated with the same entry point the deploy
          uses (app.db.migrate), so every test run also runs the Alembic
          migrations. Shared by the whole test session.
  db      runs around every test and empties the users table afterwards,
          so each test starts from a clean database.
"""

import os

os.environ["DB_NAME"] = "smallproject_test"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.db.migrate import migrate  # noqa: E402
from app.db.session import SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def client():
    migrate()
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def db(client):
    with SessionLocal() as session:
        yield session
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE users RESTART IDENTITY"))
