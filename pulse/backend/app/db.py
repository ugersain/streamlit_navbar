"""Database setup. SQLite by default; set DATABASE_URL for Postgres in production."""
from __future__ import annotations

import os
from collections.abc import Iterator
from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker
from sqlalchemy.pool import StaticPool


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _database_url() -> str:
    url = os.environ.get("DATABASE_URL", "sqlite:///./pulse.db")
    # Hosts often hand out postgres:// URLs; SQLAlchemy needs the driver name.
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg://", 1)
    elif url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def make_engine(url: str | None = None):
    url = url or _database_url()
    if url.startswith("sqlite"):
        kwargs: dict = {"connect_args": {"check_same_thread": False}}
        if ":memory:" in url:
            kwargs["poolclass"] = StaticPool
        return create_engine(url, **kwargs)
    return create_engine(url, pool_pre_ping=True)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(200))
    name: Mapped[str] = mapped_column(String(100), default="")
    calendar_token: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SessionToken(Base):
    __tablename__ = "sessions"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class ProfileRow(Base):
    __tablename__ = "profiles"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime(1970, 1, 1, tzinfo=timezone.utc))


class Record(Base):
    """Meals, workout days, reminders and meal-plan overrides, one JSON document per row."""
    __tablename__ = "records"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    kind: Mapped[str] = mapped_column(String(20), primary_key=True)
    rid: Mapped[str] = mapped_column(String(80), primary_key=True)
    day: Mapped[str | None] = mapped_column(String(10), index=True, nullable=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ActivityLog(Base):
    """History for insights: completed sets and completed habits, one row per item per day."""
    __tablename__ = "activity_log"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    kind: Mapped[str] = mapped_column(String(10), primary_key=True)   # "set" or "habit"
    ref: Mapped[str] = mapped_column(String(80), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    label: Mapped[str] = mapped_column(String(120), default="")
    value: Mapped[float] = mapped_column(Float, default=0)


class Database:
    def __init__(self, url: str | None = None):
        self.engine = make_engine(url)
        self.factory = sessionmaker(self.engine, expire_on_commit=False)
        Base.metadata.create_all(self.engine)

    def session(self) -> Iterator[Session]:
        with self.factory() as session:
            yield session


_database: Database | None = None


def get_database() -> Database:
    global _database
    if _database is None:
        _database = Database()
    return _database


def set_database(database: Database | None) -> None:
    global _database
    _database = database


def get_session() -> Iterator[Session]:
    yield from get_database().session()
