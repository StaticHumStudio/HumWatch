"""Populate and update the machine_info table on startup."""

import logging
import platform
import socket
from datetime import datetime, timezone

import psutil

from agent import __version__
from agent.database import get_db

logger = logging.getLogger("humwatch.services.machine_info")


def _get_tailscale_ip() -> str:
    """Attempt to find the Tailscale interface IP."""
    try:
        addrs = psutil.net_if_addrs()
        # Look for interfaces named "Tailscale" or similar
        for iface_name, iface_addrs in addrs.items():
            if "tailscale" in iface_name.lower():
                for addr in iface_addrs:
                    # AF_INET = IPv4
                    if addr.family.name == "AF_INET":
                        return addr.address
    except Exception:
        pass
    return ""


async def update_machine_info(gpu_name: str = None):
    """Insert or update the machine_info row."""
    db = await get_db()

    hostname = socket.gethostname()
    os_version = platform.platform()
    cpu_name = platform.processor() or "Unknown CPU"
    total_ram_mb = int(psutil.virtual_memory().total / (1024 * 1024))
    tailscale_ip = _get_tailscale_ip()
    boot_time = datetime.fromtimestamp(psutil.boot_time(), tz=timezone.utc).isoformat()
    now = datetime.now(timezone.utc).isoformat()

    await db.execute(
        """INSERT OR REPLACE INTO machine_info
        (id, hostname, os_version, cpu_name, gpu_name, total_ram_mb,
         tailscale_ip, agent_version, last_boot, updated_at)
        VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (hostname, os_version, cpu_name, gpu_name, total_ram_mb,
         tailscale_ip, __version__, boot_time, now),
    )
    await db.commit()
    logger.info("Machine info updated: %s (%s)", hostname, os_version)
