"""Nightly report job (placeholder; the real report is built in step 8).

Reuses the backend's settings and models, so it reads the same DB_* environment variables.
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select

from app.db.session import SessionLocal
from app.models.user import User


def main() -> None:
    since = datetime.now(timezone.utc) - timedelta(days=1)
    with SessionLocal() as db:
        total = db.scalar(select(func.count()).select_from(User))
        new = db.scalar(select(func.count()).select_from(User).where(User.created_at >= since))
    print(f"Nightly report: {total} users total, {new} new in the last 24h")


if __name__ == "__main__":
    main()
