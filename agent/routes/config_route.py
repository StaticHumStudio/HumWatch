"""Configuration endpoint."""

from dataclasses import asdict

from fastapi import APIRouter

from agent.config import get_config

router = APIRouter()


@router.get("/config")
async def get_configuration():
    config = get_config()
    return {
        "collection_interval_seconds": config.collection_interval_seconds,
        "retention_days": config.retention_days,
        "port": config.port,
        "enable_categories": config.enable_categories,
        "alert_thresholds": asdict(config.alert_thresholds),
    }
