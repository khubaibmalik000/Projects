from __future__ import annotations

import pytest
from sqlalchemy.orm import sessionmaker

from aiops.db import init_db, make_engine


@pytest.fixture
def session_factory():
    """A fresh isolated in-memory SQLite DB per test."""
    engine = make_engine("sqlite:///:memory:")
    init_db(engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)
