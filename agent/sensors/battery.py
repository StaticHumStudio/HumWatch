"""Battery metrics: charge, status, wear, voltage, temperature, cycles."""

import logging
from typing import List, Optional

import psutil

from agent.sensors.base import BaseSensor, MetricReading

logger = logging.getLogger("humwatch.sensors.battery")


class BatterySensor(BaseSensor):

    def __init__(self):
        self._has_battery: Optional[bool] = None

    def is_available(self) -> bool:
        if self._has_battery is None:
            try:
                self._has_battery = psutil.sensors_battery() is not None
            except Exception:
                self._has_battery = False
        return self._has_battery

    def collect(self) -> List[MetricReading]:
        readings: List[MetricReading] = []

        try:
            bat = psutil.sensors_battery()
        except Exception:
            self._has_battery = False
            return readings
        if bat is None:
            self._has_battery = False
            return readings

        self._has_battery = True
        readings.append(MetricReading("battery", "battery_percent", bat.percent, "%"))
        readings.append(MetricReading("battery", "battery_plugged", 1.0 if bat.power_plugged else 0.0, "bool"))

        if bat.secsleft > 0 and not bat.power_plugged:
            readings.append(MetricReading("battery", "battery_time_remaining", bat.secsleft, "s"))

        return readings

    def collect_lhm(self, lhm_data: dict) -> List[MetricReading]:
        """Collect LHM-sourced battery metrics (voltage, charge rate, capacity, temp, cycles)."""
        readings: List[MetricReading] = []

        lhm_metrics = {
            "battery_voltage": "V",
            "battery_charge_rate": "W",
            "battery_current": "A",
            "battery_designed_capacity": "mWh",
            "battery_current_capacity": "mWh",
            "battery_remaining_capacity": "mWh",
            "battery_temp": "°C",
            "battery_cycle_count": "",
            "battery_charge_level": "%",
            "battery_degradation": "%",
        }

        for key, unit in lhm_metrics.items():
            value = lhm_data.get(key)
            if value is not None:
                readings.append(MetricReading("battery", key, value, unit))

        # Compute wear level if both capacities available
        designed = lhm_data.get("battery_designed_capacity")
        current = lhm_data.get("battery_current_capacity")
        if designed and current and designed > 0:
            wear = (current / designed) * 100.0
            readings.append(MetricReading("battery", "battery_wear_level", round(wear, 1), "%"))

        return readings
