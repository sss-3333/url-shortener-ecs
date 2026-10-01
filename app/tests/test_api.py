import pytest
from fastapi.testclient import TestClient

from src import cache, main


class FakeBackend:
    """In-memory stand-ins for Postgres, Redis and SQS, so the tests need no running services."""

    def __init__(self):
        self.urls, self.cache, self.events, self.db_reads = {}, {}, [], 0

    def put_mapping(self, short_id, url):
        self.urls[short_id] = {"id": short_id, "url": url, "clicks": 0}

    def get_mapping(self, short_id):
        self.db_reads += 1
        return self.urls.get(short_id)

    def increment_clicks(self, short_id):
        if short_id in self.urls:
            self.urls[short_id]["clicks"] += 1

    def get_cached_url(self, short_id):
        return self.cache.get(short_id)

    def cache_url(self, short_id, url):
        self.cache[short_id] = url

    def publish_click_event(self, **event):
        self.events.append(event)


@pytest.fixture
def backend(monkeypatch):
    fake = FakeBackend()
    for name in ["put_mapping", "get_mapping", "increment_clicks",
                 "get_cached_url", "cache_url", "publish_click_event"]:
        monkeypatch.setattr(main, name, getattr(fake, name))
    monkeypatch.setattr(main, "get_backend_type", lambda: "postgres")
    return fake


@pytest.fixture
def client(backend):
    return TestClient(main.app)


def shorten(client, url="https://example.com"):
    return client.post("/shorten", json={"url": url}).json()["short"]


def test_healthz(client):
    assert client.get("/healthz").json()["status"] == "ok"


def test_shorten_requires_url(client):
    assert client.post("/shorten", json={}).status_code == 400


def test_cache_miss_reads_db_then_fills_cache(client, backend):
    code = shorten(client)
    backend.cache.clear()

    resp = client.get(f"/{code}", follow_redirects=False)

    assert resp.status_code == 307
    assert resp.headers["location"] == "https://example.com"
    assert backend.db_reads == 1
    assert code in backend.cache


def test_cache_hit_skips_db(client, backend):
    backend.cache["abc12345"] = "https://example.com"

    assert client.get("/abc12345", follow_redirects=False).status_code == 307
    assert backend.db_reads == 0


def test_redirect_counts_click_and_publishes_event(client, backend):
    code = shorten(client)
    client.get(f"/{code}", follow_redirects=False)

    assert backend.urls[code]["clicks"] == 1
    assert backend.events[0]["short_code"] == code


def test_unknown_code_is_404_and_publishes_nothing(client, backend):
    assert client.get("/nope1234", follow_redirects=False).status_code == 404
    assert backend.events == []


def test_redis_failure_falls_back_instead_of_erroring(monkeypatch):
    class BrokenRedis:
        def get(self, key):
            raise ConnectionError("redis is down")

    monkeypatch.setattr(cache, "_client", BrokenRedis())
    monkeypatch.setattr(cache, "_initialised", True)

    assert cache.get_cached_url("abc12345") is None