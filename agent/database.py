"""SQLite database management for HumWatch."""

import logging
from pathlib import Path
from typing import Optional

import aiosqlite

from agent.config import get_config

logger = logging.getLogger("humwatch.database")

# Module-level connection
_db: Optional[aiosqlite.Connection] = None

SCHEMA_SQL = """
-- Machine identity (one row, updated on each startup)
CREATE TABLE IF NOT EXISTS machine_info (
    id INTEGER PRIMARY KEY DEFAULT 1,
    hostname TEXT NOT NULL,
    os_version TEXT,
    cpu_name TEXT,
    gpu_name TEXT,
    total_ram_mb INTEGER,
    network_ip TEXT,
    agent_version TEXT,
    last_boot TEXT,
    updated_at TEXT NOT NULL
);

-- Time-series metric storage
CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    category TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    value REAL NOT NULL,
    unit TEXT
);

-- Indices for query performance
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp);
CREATE INDEX IF NOT EXISTS idx_metrics_category_timestamp ON metrics(category, timestamp);
CREATE INDEX IF NOT EXISTS idx_metrics_name_timestamp ON metrics(metric_name, timestamp);

-- Snapshot of top processes at each collection interval
CREATE TABLE IF NOT EXISTS process_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    pid INTEGER NOT NULL,
    name TEXT NOT NULL,
    cpu_percent REAL,
    memory_mb REAL
);

CREATE INDEX IF NOT EXISTS idx_process_timestamp ON process_snapshots(timestamp);
"""


async def init_db() -> aiosqlite.Connection:
    """Initialize the SQLite database with WAL mode and schema."""
    global _db

    config = get_config()
    db_path = config.resolved_db_path

    # Ensure parent directory exists
    db_path.parent.mkdir(parents=True, exist_ok=True)

    logger.info("Opening database at %s", db_path)
    _db = await aiosqlite.connect(str(db_path))

    # Configure WAL mode and performance pragmas
    await _db.execute("PRAGMA journal_mode=WAL")
    await _db.execute("PRAGMA synchronous=NORMAL")
    await _db.execute("PRAGMA cache_size=-64000")  # 64MB cache
    await _db.execute("PRAGMA busy_timeout=5000")
    await _db.execute("PRAGMA temp_store=MEMORY")

    # Create schema
    await _db.executescript(SCHEMA_SQL)
    await _db.commit()

    # Run one-time migrations
    await _migrate_schema(_db)

    logger.info("Database initialized successfully")
    return _db


async def _migrate_schema(db: aiosqlite.Connection) -> None:
    """Run one-time schema migrations for existing installs."""
    cursor = await db.execute("PRAGMA table_info(machine_info)")
    columns = [row[1] for row in await cursor.fetchall()]

    if "tailscale_ip" in columns and "network_ip" not in columns:
        await db.execute(
            "ALTER TABLE machine_info RENAME COLUMN tailscale_ip TO network_ip"
        )
        await db.commit()
        logger.info("Migrated column tailscale_ip -> network_ip")


async def get_db() -> aiosqlite.Connection:
    """Get the active database connection."""
    if _db is None:
        raise RuntimeError("Database not initialized. Call init_db() first.")
    return _db


async def close_db() -> None:
    """Close the database connection."""
    global _db
    if _db is not None:
        await _db.close()
        _db = None
        logger.info("Database connection closed")
