"""Fan speed metrics (LHM only)."""

import logging
from typing import List

from agent.sensors.base import BaseSensor, MetricReading

logger = logging.getLogger("humwatch.sensors.fan")


class FanSensor(BaseSensor):
    """Fan sensor — entirely dependent on LibreHardwareMonitor."""

    def __init__(self):
        self._available = False

    def is_available(self) -> bool:
        return self._available

    def collect(self) -> List[MetricReading]:
        return []

    def collect_lhm(self, lhm_data: dict) -> List[MetricReading]:
        """Collect LHM-sourced fan metrics."""
        readings: List[MetricReading] = []

        for key, value in lhm_data.items():
            if value is None:
                continue
            if key.startswith("fan_") and key.endswith("_speed"):
                readings.append(MetricReading("fan", key, value, "RPM"))
                self._available = True

        return readings
