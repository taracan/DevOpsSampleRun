"""POST /api/v1/auth/register: the registration endpoint, end to end.

Each test goes through the real app and the real database: request
validation, the user service, and the users table.
"""

from sqlalchemy import select

from app.models.user import User

URL = "/api/v1/auth/register"
ALICE = {"name": "Alice", "email": "alice@example.com", "password": "secret123"}


def test_register_creates_user(client, db):
    response = client.post(URL, json=ALICE)

    assert response.status_code == 201
    body = response.json()
    assert body["message"] == "Registered successfully"
    assert body["name"] == "Alice"
    assert body["email"] == "alice@example.com"
    assert isinstance(body["id"], int)
    assert "password" not in body
    assert "password_hash" not in body

    user = db.scalar(select(User).where(User.email == "alice@example.com"))
    assert user is not None
    assert user.name == "Alice"


def test_register_stores_hashed_password(client, db):
    client.post(URL, json=ALICE)

    user = db.scalar(select(User).where(User.email == "alice@example.com"))
    assert user.password_hash != "secret123"
    salt, digest = user.password_hash.split("$")
    assert len(salt) == 32
    assert len(digest) == 64


def test_register_duplicate_email_is_rejected(client):
    assert client.post(URL, json=ALICE).status_code == 201

    response = client.post(URL, json={**ALICE, "name": "Alice Again"})

    assert response.status_code == 400
    assert response.json() == {"detail": "Email is already registered"}


def test_register_invalid_email_is_rejected(client):
    response = client.post(URL, json={**ALICE, "email": "not-an-email"})

    assert response.status_code == 422


def test_register_short_password_is_rejected(client):
    response = client.post(URL, json={**ALICE, "password": "12345"})

    assert response.status_code == 422


def test_register_missing_field_is_rejected(client):
    response = client.post(URL, json={"email": "alice@example.com", "password": "secret123"})

    assert response.status_code == 422
