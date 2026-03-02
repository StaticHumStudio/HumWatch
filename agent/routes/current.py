"""Current readings endpoint."""

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from agent.collector import get_latest_readings

router = APIRouter()


@router.get("/current")
async def get_current():
    readings = get_latest_readings()
    if not readings:
        return JSONResponse(
            status_code=503,
            content={"error": "No data collected yet. Please wait for the first collection cycle."},
        )
    return readings
