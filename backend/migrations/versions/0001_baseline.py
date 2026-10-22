"""Baseline: the users table as it already exists in production.

Revision ID: 0001
Revises: (none, this is the first migration)
Create Date: 2026-10-22

Before Alembic, the app created this table itself at start-up
(Base.metadata.create_all). This script describes exactly that table, so:
  - a NEW, empty database gets it by running this migration;
  - an EXISTING database that already has it (production, your laptop) is
    only marked as being at this revision ("stamped") by app/db/migrate.py,
    without running it, so no data is touched.
tests/test_migrations.py checks this script still matches app/models/.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
