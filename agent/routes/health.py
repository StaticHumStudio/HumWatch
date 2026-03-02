"""Health check endpoint."""

import time

from fastapi import APIRouter

from agent import __version__

router = APIRouter()


@router.get("/health")
async def health_check():
    from agent.main import SERVER_START_TIME
    uptime = time.time() - SERVER_START_TIME if SERVER_START_TIME > 0 else 0
    return {
        "status": "ok",
        "version": __version__,
        "uptime_seconds": round(uptime, 1),
    }
