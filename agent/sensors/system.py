"""System metrics: uptime, boot time."""

import time
from datetime import datetime, timezone
from typing import List

import psutil

from agent.sensors.base import BaseSensor, MetricReading


class SystemSensor(BaseSensor):

    def is_available(self) -> bool:
        return True

    def collect(self) -> List[MetricReading]:
        boot_ts = psutil.boot_time()
        uptime = time.time() - boot_ts
        boot_iso = datetime.fromtimestamp(boot_ts, tz=timezone.utc).isoformat()

        return [
            MetricReading("system", "uptime_seconds", uptime, "s"),
            MetricReading("system", "boot_time", boot_ts, "s"),
        ]
