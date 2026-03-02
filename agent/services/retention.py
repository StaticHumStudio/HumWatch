"""Data retention service — hourly cleanup of old records."""

import asyncio
import logging
from datetime import datetime, timedelta, timezone

from agent.config import get_config
from agent.database import get_db

logger = logging.getLogger("humwatch.services.retention")


async def start_retention_loop():
    """Run the retention cleanup every hour."""
    config = get_config()

    while True:
        try:
            await asyncio.sleep(3600)  # 1 hour
            await run_cleanup(config.retention_days)
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error("Retention cleanup error: %s", e)
            await asyncio.sleep(60)  # Retry after 1 minute on error


async def run_cleanup(retention_days: int):
    """Delete metrics and process snapshots older than retention_days."""
    db = await get_db()
    cutoff = (datetime.now(timezone.utc) - timedelta(days=retention_days)).isoformat()

    cursor = await db.execute("DELETE FROM metrics WHERE timestamp < ?", (cutoff,))
    metrics_deleted = cursor.rowcount

    cursor = await db.execute("DELETE FROM process_snapshots WHERE timestamp < ?", (cutoff,))
    procs_deleted = cursor.rowcount

    await db.commit()

    if metrics_deleted > 0 or procs_deleted > 0:
        logger.info(
            "Retention cleanup: deleted %d metrics, %d process snapshots (cutoff: %s)",
            metrics_deleted, procs_deleted, cutoff,
        )
