"""Configuration loading for HumWatch agent."""

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

# Project root is one level up from agent/
PROJECT_ROOT = Path(__file__).resolve().parent.parent


@dataclass
class AlertThresholds:
    cpu_temp_warn: float = 85.0
    cpu_temp_critical: float = 95.0
    gpu_temp_warn: float = 80.0
    gpu_temp_critical: float = 90.0
    ram_percent_warn: float = 85.0
    ram_percent_critical: float = 95.0
    disk_percent_warn: float = 85.0
    disk_percent_critical: float = 95.0
    battery_low_warn: float = 20.0
    battery_low_critical: float = 10.0


@dataclass
class HumWatchConfig:
    port: int = 9100
    collection_interval_seconds: int = 10
    retention_days: int = 7
    db_path: str = "./humwatch.db"
    theme_override: Optional[str] = None
    alert_thresholds: AlertThresholds = field(default_factory=AlertThresholds)
    process_snapshot_count: int = 10
    enable_categories: List[str] = field(
        default_factory=lambda: [
            "cpu", "gpu", "memory", "disk", "network", "fan", "battery", "system"
        ]
    )

    @property
    def resolved_db_path(self) -> Path:
        """Resolve db_path relative to project root."""
        p = Path(self.db_path)
        if p.is_absolute():
            return p
        return PROJECT_ROOT / p


def load_config() -> HumWatchConfig:
    """Load configuration from config.json and environment variable overrides."""
    config_file = PROJECT_ROOT / "config.json"
    data: Dict = {}

    if config_file.exists():
        with open(config_file, "r", encoding="utf-8") as f:
            data = json.load(f)

    # Build alert thresholds
    thresholds_data = data.get("alert_thresholds", {})
    thresholds = AlertThresholds(**{
        k: v for k, v in thresholds_data.items()
        if hasattr(AlertThresholds, k)
    })

    config = HumWatchConfig(
        port=data.get("port", 9100),
        collection_interval_seconds=data.get("collection_interval_seconds", 10),
        retention_days=data.get("retention_days", 7),
        db_path=data.get("db_path", "./humwatch.db"),
        theme_override=data.get("theme_override"),
        alert_thresholds=thresholds,
        process_snapshot_count=data.get("process_snapshot_count", 10),
        enable_categories=data.get("enable_categories", [
            "cpu", "gpu", "memory", "disk", "network", "fan", "battery", "system"
        ]),
    )

    # Environment variable overrides
    env_port = os.environ.get("HUMWATCH_PORT")
    if env_port is not None:
        config.port = int(env_port)

    env_db = os.environ.get("HUMWATCH_DB")
    if env_db is not None:
        config.db_path = env_db

    env_interval = os.environ.get("HUMWATCH_INTERVAL")
    if env_interval is not None:
        config.collection_interval_seconds = int(env_interval)

    return config


# Module-level singleton
_config: Optional[HumWatchConfig] = None


def get_config() -> HumWatchConfig:
    """Get the application configuration (singleton)."""
    global _config
    if _config is None:
        _config = load_config()
    return _config
