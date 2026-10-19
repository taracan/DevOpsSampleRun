"""hash_password: PBKDF2-SHA256 with a random salt, stored as "salt$digest"."""

import hashlib

from app.core.security import hash_password


def test_hash_has_salt_and_digest():
    salt, digest = hash_password("secret123").split("$")

    assert len(salt) == 32  # 16 random bytes, hex
    assert len(digest) == 64  # SHA-256, hex


def test_hash_matches_pbkdf2_of_the_salt():
    salt, digest = hash_password("secret123").split("$")

    expected = hashlib.pbkdf2_hmac("sha256", b"secret123", salt.encode(), 200_000).hex()
    assert digest == expected


def test_same_password_gets_a_different_salt():
    assert hash_password("secret123") != hash_password("secret123")
