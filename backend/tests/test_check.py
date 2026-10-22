"""The restore drill's data check (app/db/check.py), against the test database.

The test database is migrated and its users table emptied after each test
(conftest.py), so each test sets up exactly the situation it needs.
"""

from sqlalchemy import text

from app.db.check import check
from app.db.session import engine

ALICE = {"name": "Alice", "email": "alice@example.com", "password": "secret123"}


def test_passes_when_up_to_date_and_has_data(client, capsys):
    client.post("/api/v1/auth/register", json=ALICE)

    assert check() is True
    assert "OK" in capsys.readouterr().out


def test_fails_when_users_table_is_empty(client, capsys):
    assert check() is False
    assert "users table is empty" in capsys.readouterr().out


def test_fails_when_not_at_newest_migration(client, capsys):
    client.post("/api/v1/auth/register", json=ALICE)
    with engine.begin() as conn:
        conn.execute(text("UPDATE alembic_version SET version_num = 'old'"))
    try:
        assert check() is False
        assert "not at the newest migration" in capsys.readouterr().out
    finally:
        with engine.begin() as conn:
            conn.execute(text("UPDATE alembic_version SET version_num = '0001'"))
