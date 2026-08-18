"""FastAPI application entrypoint. Run with:

    uvicorn aiops.api.main:app --reload
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from aiops import __version__
from aiops.api.routes import health, incidents, logs, metrics, topology
from aiops.db import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="AIOps Incident Intelligence Platform",
    version=__version__,
    description=(
        "Streaming anomaly detection, log template mining, alert "
        "correlation, and remediation for infrastructure telemetry."
    ),
    lifespan=lifespan,
)

app.include_router(health.router, prefix="/v1")
app.include_router(metrics.router, prefix="/v1")
app.include_router(logs.router, prefix="/v1")
app.include_router(incidents.router, prefix="/v1")
app.include_router(topology.router, prefix="/v1")
