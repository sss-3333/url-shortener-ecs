import pytest

from src import db


@pytest.fixture
def fresh_db(monkeypatch):
    """Reset the cached backend and replace both real backends with labelled fakes."""
    monkeypatch.setattr(db, "_backend", None)
    monkeypatch.setattr(db, "_init_postgres", lambda: {"type": "postgres"})
    monkeypatch.setattr(db, "_init_dynamodb", lambda: {"type": "dynamodb"})
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("TABLE_NAME", raising=False)
    return monkeypatch


def test_no_database_configured_raises(fresh_db):
    with pytest.raises(RuntimeError):
        db.get_backend_type()


def test_database_url_selects_postgres(fresh_db):
    fresh_db.setenv("DATABASE_URL", "postgresql://user:pass@host:5432/db")
    assert db.get_backend_type() == "postgres"


def test_table_name_selects_dynamodb(fresh_db):
    fresh_db.setenv("TABLE_NAME", "urls")
    assert db.get_backend_type() == "dynamodb"


def test_postgres_wins_when_both_are_set(fresh_db):
    fresh_db.setenv("DATABASE_URL", "postgresql://user:pass@host:5432/db")
    fresh_db.setenv("TABLE_NAME", "urls")
    assert db.get_backend_type() == "postgres"