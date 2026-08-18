"""SQLAlchemy engine/session wiring. SQLite by default; swap AIOPS_DATABASE_URL
for a Postgres DSN in a multi-instance deployment.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from aiops.config import settings
from aiops.models import Base


def make_engine(database_url: str | None = None):
    url = database_url or settings.database_url
    is_sqlite = url.startswith("sqlite")
    is_memory = is_sqlite and ":memory:" in url
    kwargs: dict = {}
    if is_sqlite:
        kwargs["connect_args"] = {"check_same_thread": False}
    if is_memory:
        # A plain in-memory SQLite DB is per-connection; without a shared
        # pool, each new connection (e.g. from a different thread, as
        # FastAPI's threadpool uses) sees an empty, table-less database.
        kwargs["poolclass"] = StaticPool
    return create_engine(url, **kwargs)


engine = make_engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def init_db(bind_engine=None) -> None:
    Base.metadata.create_all(bind=bind_engine or engine)


@contextmanager
def session_scope(session_factory=None) -> Iterator[Session]:
    factory = session_factory or SessionLocal
    session = factory()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
