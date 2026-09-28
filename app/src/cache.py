"""
Redis cache for short code -> URL lookups.

Set REDIS_URL to enable. Without it, or if Redis is unreachable,
lookups fall back to the database.
"""

import os
import logging

logger = logging.getLogger(__name__)

CACHE_TTL_SECONDS = 3600

_client = None
_initialised = False


def _get_client():
    global _client, _initialised
    if _initialised:
        return _client
    _initialised = True

    redis_url = os.environ.get("REDIS_URL")
    if not redis_url:
        return None

    import redis
    _client = redis.Redis.from_url(
        redis_url,
        socket_timeout=0.5,
        socket_connect_timeout=0.5,
        decode_responses=True,
    )
    return _client


def get_cached_url(short_id: str):
    client = _get_client()
    if client is None:
        return None
    try:
        return client.get(f"url:{short_id}")
    except Exception as e:
        logger.warning(f"Redis get failed, falling back to database: {e}")
        return None


def cache_url(short_id: str, url: str):
    client = _get_client()
    if client is None:
        return
    try:
        client.set(f"url:{short_id}", url, ex=CACHE_TTL_SECONDS)
    except Exception as e:
        logger.warning(f"Redis set failed: {e}")