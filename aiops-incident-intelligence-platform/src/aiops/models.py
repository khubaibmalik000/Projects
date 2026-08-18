"""ORM models persisting incidents, their signals, and remediation actions."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class IncidentRecord(Base):
    __tablename__ = "incidents"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    status: Mapped[str] = mapped_column(String(16), default="open")
    severity: Mapped[str] = mapped_column(String(16), default="info")
    entities: Mapped[list[str]] = mapped_column(JSON, default=list)
    probable_root_cause: Mapped[str | None] = mapped_column(String(128), nullable=True)
    opened_at: Mapped[datetime] = mapped_column(DateTime)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime)

    signals: Mapped[list[SignalRecord]] = relationship(
        back_populates="incident", cascade="all, delete-orphan"
    )
    remediations: Mapped[list[RemediationRecord]] = relationship(
        back_populates="incident", cascade="all, delete-orphan"
    )

    @property
    def signal_count(self) -> int:
        return len(self.signals)


class SignalRecord(Base):
    __tablename__ = "signals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    incident_id: Mapped[str] = mapped_column(ForeignKey("incidents.id"))
    entity: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(16))
    description: Mapped[str] = mapped_column(String(512))
    severity: Mapped[str] = mapped_column(String(16))
    score: Mapped[float] = mapped_column(Float)
    source_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime)

    incident: Mapped[IncidentRecord] = relationship(back_populates="signals")


class RemediationRecord(Base):
    __tablename__ = "remediations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    incident_id: Mapped[str] = mapped_column(ForeignKey("incidents.id"))
    rule_name: Mapped[str] = mapped_column(String(128))
    action: Mapped[str] = mapped_column(String(64))
    dry_run: Mapped[bool] = mapped_column(Boolean, default=True)
    success: Mapped[bool] = mapped_column(Boolean)
    message: Mapped[str] = mapped_column(String(512))
    executed_at: Mapped[datetime] = mapped_column(DateTime)

    incident: Mapped[IncidentRecord] = relationship(back_populates="remediations")
