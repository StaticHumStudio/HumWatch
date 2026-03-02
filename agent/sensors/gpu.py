"""GPU metrics: temperature, load, VRAM, clocks, power, fan (LHM only)."""

import logging
from typing import List

from agent.sensors.base import BaseSensor, MetricReading

logger = logging.getLogger("humwatch.sensors.gpu")


class GpuSensor(BaseSensor):
    """GPU sensor — entirely dependent on LibreHardwareMonitor."""

    def __init__(self):
        self._available = False

    def is_available(self) -> bool:
        return self._available

    def set_available(self, available: bool):
        self._available = available

    def collect(self) -> List[MetricReading]:
        # GPU data comes exclusively from LHM, collected via collect_lhm
        return []

    def collect_lhm(self, lhm_data: dict) -> List[MetricReading]:
        """Collect LHM-sourced GPU metrics."""
        readings: List[MetricReading] = []

        metric_units = {
            "gpu_temp": "°C",
            "gpu_load": "%",
            "gpu_clock_core": "MHz",
            "gpu_clock_memory": "MHz",
            "gpu_vram_used": "MB",
            "gpu_vram_total": "MB",
            "gpu_power": "W",
            "gpu_fan_speed": "RPM",
        }

        for key, unit in metric_units.items():
            value = lhm_data.get(key)
            if value is not None:
                readings.append(MetricReading("gpu", key, value, unit))

        if readings:
            self._available = True

        return readings
