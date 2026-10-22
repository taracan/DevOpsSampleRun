"""Readiness check (GET /api/v1/ready): is the database reachable?

The first test uses the real test database, so it must answer 200. The
second swaps the database check for one that always fails (a FastAPI
dependency override), to prove the endpoint then answers 503, which is what
makes the deploy's smoke test fail.
"""

from app.api.v1.endpoints.health import check_database
from app.main import app


def test_ready_when_database_is_reachable(client):
    response = client.get("/api/v1/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "db": "ok"}


def test_not_ready_when_database_is_unreachable(client):
    app.dependency_overrides[check_database] = lambda: False
    try:
        response = client.get("/api/v1/ready")
    finally:
        app.dependency_overrides.pop(check_database)

    assert response.status_code == 503
    assert response.json() == {"status": "unavailable", "db": "error"}
