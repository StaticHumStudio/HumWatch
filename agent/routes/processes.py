"""Process snapshot endpoints."""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Query

from agent.collector import get_latest_processes
from agent.database import get_db

router = APIRouter()


@router.get("/processes")
async def get_processes():
    """Get the most recent process snapshot."""
    return {"processes": get_latest_processes()}


@router.get("/processes/history")
async def get_processes_history(
    from_ts: Optional[str] = Query(None, alias="from"),
    to_ts: Optional[str] = Query(None, alias="to"),
):
    """Get process snapshots within a time range."""
    now = datetime.now(timezone.utc)

    if to_ts is None:
        to_ts = now.isoformat().replace("+00:00", "Z")
    if from_ts is None:
        from_ts = (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z")

    db = await get_db()
    cursor = await db.execute(
        """SELECT timestamp, pid, name, cpu_percent, memory_mb
        FROM process_snapshots
        WHERE timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp, cpu_percent DESC""",
        (from_ts, to_ts),
    )
    rows = await cursor.fetchall()

    # Group by timestamp
    snapshots = {}
    for row in rows:
        ts = row[0]
        if ts not in snapshots:
            snapshots[ts] = []
        snapshots[ts].append({
            "pid": row[1],
            "name": row[2],
            "cpu_percent": row[3],
            "memory_mb": row[4],
        })

    return {"snapshots": snapshots}
