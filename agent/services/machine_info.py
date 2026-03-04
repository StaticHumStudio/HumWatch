"""Populate and update the machine_info table on startup."""

import ipaddress
import logging
import platform
import socket
from datetime import datetime, timezone

import psutil

from agent import __version__
from agent.database import get_db

logger = logging.getLogger("humwatch.services.machine_info")

# Known overlay/VPN interface name patterns (case-insensitive substring match)
_OVERLAY_IFACE_PATTERNS = [
    "tailscale",
    "zerotier",
    "wg",          # WireGuard
    "nebula",
    "hamachi",
    "tun",         # Generic TUN interfaces (OpenVPN, etc.)
]

# Known overlay/VPN IP ranges (high-confidence, won't match typical LANs)
_OVERLAY_RANGES = [
    ipaddress.ip_network("100.64.0.0/10"),   # CGNAT (Tailscale, some VPNs)
    ipaddress.ip_network("25.0.0.0/8"),      # Hamachi
]


def _get_network_ip() -> str:
    """Detect the best overlay/VPN IP, falling back to LAN IP."""
    try:
        addrs = psutil.net_if_addrs()

        overlay_ips = []
        lan_ips = []

        for iface_name, iface_addrs in addrs.items():
            name_lower = iface_name.lower()
            is_overlay_iface = any(
                pat in name_lower for pat in _OVERLAY_IFACE_PATTERNS
            )

            for addr in iface_addrs:
                if addr.family.name != "AF_INET":
                    continue
                ip_str = addr.address
                if ip_str.startswith("127."):
                    continue

                try:
                    ip_obj = ipaddress.ip_address(ip_str)
                except ValueError:
                    continue

                is_overlay_range = any(
                    ip_obj in net for net in _OVERLAY_RANGES
                )

                if is_overlay_iface or is_overlay_range:
                    overlay_ips.append(ip_str)
                else:
                    lan_ips.append(ip_str)

        if overlay_ips:
            return overlay_ips[0]
        if lan_ips:
            return lan_ips[0]
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
    network_ip = _get_network_ip()
    boot_time = datetime.fromtimestamp(psutil.boot_time(), tz=timezone.utc).isoformat()
    now = datetime.now(timezone.utc).isoformat()

    await db.execute(
        """INSERT OR REPLACE INTO machine_info
        (id, hostname, os_version, cpu_name, gpu_name, total_ram_mb,
         network_ip, agent_version, last_boot, updated_at)
        VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (hostname, os_version, cpu_name, gpu_name, total_ram_mb,
         network_ip, __version__, boot_time, now),
    )
    await db.commit()
    logger.info("Machine info updated: %s (%s), network_ip=%s", hostname, os_version, network_ip)
