"""Readiness check: GET /api/v1/ready ("can this backend really serve requests?").

Two kinds of health check, on purpose:
  /health          liveness (app/main.py): "the process is up". Never touches
                   the database. The load balancer uses it, so a short
                   database blip doesn't make ECS kill healthy tasks.
  /api/v1/ready    readiness (this file): "the process is up AND can reach
                   the database". The deploy workflow's smoke test calls it
                   through CloudFront, so a release with broken database
                   settings fails the deploy instead of passing it.

The check opens a brand-new connection (no connection pool) and runs
SELECT 1, giving up after 3 seconds. A fresh connection matters: pooled
connections can stay open after the RDS password rotates, so only a new
login shows whether the password this task holds still works.

Answers:
  200 {"status": "ok", "db": "ok"}
  503 {"status": "unavailable", "db": "error"}  (the reason goes to the log)
"""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, status
from fastapi.responses import JSONResponse
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool

from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])

# NullPool: every check logs in from scratch, then closes the connection.
_ready_engine = create_engine(
    settings.database_url(), poolclass=NullPool, connect_args={"connect_timeout": 3}
)


def check_database() -> bool:
    """True if a new connection can log in and run SELECT 1."""
    try:
        with _ready_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception:
        logger.exception("Readiness check: database unreachable")
        return False
    return True


@router.get("/ready")
def ready(db_ok: Annotated[bool, Depends(check_database)]):
    if db_ok:
        return {"status": "ok", "db": "ok"}
    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content={"status": "unavailable", "db": "error"},
    )
