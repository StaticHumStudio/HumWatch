"""Machine info endpoint."""

import time

import psutil
from fastapi import APIRouter

from agent.collector import get_lhm_status
from agent.database import get_db

router = APIRouter()


@router.get("/info")
async def get_info():
    db = await get_db()
    cursor = await db.execute("SELECT * FROM machine_info WHERE id = 1")
    row = await cursor.fetchone()

    if row is None:
        return {"error": "Machine info not yet available"}

    columns = [desc[0] for desc in cursor.description]
    info = dict(zip(columns, row))

    # Add computed uptime
    info["uptime_seconds"] = round(time.time() - psutil.boot_time(), 1)

    # Add LHM status
    lhm = get_lhm_status()
    info["lhm_available"] = lhm["lhm_available"]

    return info
