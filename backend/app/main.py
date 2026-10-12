"""FastAPI application entry point (uvicorn runs `app.main:app`).

- On start-up, creates the database and tables if missing (lifespan).
- Mounts the API routes under /api/v1 (e.g. POST /api/v1/auth/register).
- Health checks, both returning {"status": "ok"}:
    /health         used by the load balancer, which calls the container directly
    /api/v1/health  used through CloudFront, which only forwards /api/* to the
                    backend (the deploy workflow's smoke test calls this one)
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.db.init_db import create_database


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_database()
    yield


app = FastAPI(title=settings.APP_NAME, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_PREFIX)


@app.get("/health", tags=["health"])
@app.get(f"{settings.API_V1_PREFIX}/health", tags=["health"])
def health():
    return {"status": "ok"}
