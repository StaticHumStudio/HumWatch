"""Historical data endpoints."""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Query

from agent.database import get_db
from agent.services.downsampler import build_history_query, compute_resolution

router = APIRouter()


def _to_utc_iso(ts: str) -> str:
    """Normalize SQLite timestamp to ISO 8601 with Z suffix."""
    if not ts:
        return ts
    # SQLite stores as "YYYY-MM-DD HH:MM:SS" — convert to "YYYY-MM-DDTHH:MM:SSZ"
    s = ts.replace(" ", "T")
    if not s.endswith("Z") and "+" not in s:
        s += "Z"
    return s


@router.get("/history")
async def get_history(
    metric: str,
    from_ts: Optional[str] = Query(None, alias="from"),
    to_ts: Optional[str] = Query(None, alias="to"),
    resolution: Optional[int] = None,
):
    """Get historical data for a single metric."""
    now = datetime.now(timezone.utc)

    if to_ts is None:
        to_ts = now.isoformat().replace("+00:00", "Z")
    if from_ts is None:
        from_ts = (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z")

    # Compute time range in seconds for auto-resolution
    try:
        t_from = datetime.fromisoformat(from_ts.replace("Z", "+00:00"))
        t_to = datetime.fromisoformat(to_ts.replace("Z", "+00:00"))
        range_seconds = (t_to - t_from).total_seconds()
    except (ValueError, TypeError):
        range_seconds = 3600

    bucket = compute_resolution(range_seconds, resolution)
    sql, params = build_history_query(metric, from_ts, to_ts, bucket)

    db = await get_db()
    cursor = await db.execute(sql, params)
    rows = await cursor.fetchall()

    data = [{"timestamp": _to_utc_iso(row[0]), "value": row[1]} for row in rows]
    return data


@router.get("/history/multi")
async def get_history_multi(
    metrics: str,
    from_ts: Optional[str] = Query(None, alias="from"),
    to_ts: Optional[str] = Query(None, alias="to"),
    resolution: Optional[int] = None,
):
    """Get historical data for multiple metrics (comma-separated)."""
    now = datetime.now(timezone.utc)

    if to_ts is None:
        to_ts = now.isoformat().replace("+00:00", "Z")
    if from_ts is None:
        from_ts = (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z")

    try:
        t_from = datetime.fromisoformat(from_ts.replace("Z", "+00:00"))
        t_to = datetime.fromisoformat(to_ts.replace("Z", "+00:00"))
        range_seconds = (t_to - t_from).total_seconds()
    except (ValueError, TypeError):
        range_seconds = 3600

    bucket = compute_resolution(range_seconds, resolution)

    metric_names = [m.strip() for m in metrics.split(",") if m.strip()]
    result = {}

    db = await get_db()
    for metric_name in metric_names:
        sql, params = build_history_query(metric_name, from_ts, to_ts, bucket)
        cursor = await db.execute(sql, params)
        rows = await cursor.fetchall()
        result[metric_name] = [{"timestamp": _to_utc_iso(row[0]), "value": row[1]} for row in rows]

    return result
