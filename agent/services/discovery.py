"""Tailscale peer discovery — find other HumWatch instances on the Tailnet."""

import asyncio
import json
import logging
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Dict, List, Optional

import httpx

from agent.config import get_config

logger = logging.getLogger("humwatch.services.discovery")

DISCOVERY_INTERVAL = 60  # seconds between full scans
PROBE_TIMEOUT = 3.0      # seconds per HTTP probe
PROBE_PORT = 9100         # default HumWatch port


@dataclass
class DiscoveredPeer:
    url: str
    tailscale_ip: str
    hostname: str
    os_version: str
    cpu_name: str
    gpu_name: str
    total_ram_mb: int
    agent_version: str
    status: str        # "online" | "offline"
    last_seen: str     # ISO 8601 UTC
    is_self: bool


# Module-level state
_discovered_peers: Dict[str, DiscoveredPeer] = {}
_self_ip: str = ""


def _get_tailscale_peers() -> List[str]:
    """Run ``tailscale status --json`` and extract online peer IPv4 addresses."""
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            logger.warning(
                "tailscale status failed (exit %d): %s",
                result.returncode,
                result.stderr.strip(),
            )
            return []

        data = json.loads(result.stdout)
        peers: List[str] = []

        # Self node
        self_ips = data.get("Self", {}).get("TailscaleIPs", [])
        for ip in self_ips:
            if ":" not in ip:  # IPv4 only
                peers.append(ip)
                break

        # Peer nodes
        peer_map = data.get("Peer", {})
        for _key, peer_info in peer_map.items():
            if not peer_info.get("Online", False):
                continue
            ips = peer_info.get("TailscaleIPs", [])
            for ip in ips:
                if ":" not in ip:  # IPv4 only
                    peers.append(ip)
                    break

        return peers

    except FileNotFoundError:
        logger.info("Tailscale CLI not found — peer discovery disabled")
        return []
    except subprocess.TimeoutExpired:
        logger.warning("tailscale status timed out")
        return []
    except (json.JSONDecodeError, KeyError) as exc:
        logger.warning("Failed to parse tailscale status output: %s", exc)
        return []
    except Exception as exc:
        logger.error("Unexpected error running tailscale status: %s", exc)
        return []


async def _probe_peer(
    client: httpx.AsyncClient,
    ip: str,
    port: int,
    self_ip: str,
) -> Optional[DiscoveredPeer]:
    """Probe a single IP for a running HumWatch instance."""
    base_url = f"http://{ip}:{port}"
    now = datetime.now(timezone.utc).isoformat()

    try:
        # Health check
        resp = await client.get(f"{base_url}/api/health", timeout=PROBE_TIMEOUT)
        if resp.status_code != 200:
            return None
        health = resp.json()
        if health.get("status") != "ok":
            return None

        # Fetch detailed info
        version = health.get("version", "")
        try:
            info_resp = await client.get(f"{base_url}/api/info", timeout=PROBE_TIMEOUT)
            if info_resp.status_code == 200:
                info = info_resp.json()
            else:
                info = {}
        except Exception:
            info = {}

        return DiscoveredPeer(
            url=base_url,
            tailscale_ip=ip,
            hostname=info.get("hostname", ip),
            os_version=info.get("os_version", ""),
            cpu_name=info.get("cpu_name", ""),
            gpu_name=info.get("gpu_name", ""),
            total_ram_mb=info.get("total_ram_mb", 0),
            agent_version=info.get("agent_version", version),
            status="online",
            last_seen=now,
            is_self=(ip == self_ip),
        )

    except (httpx.TimeoutException, httpx.ConnectError, httpx.HTTPError):
        return None
    except Exception as exc:
        logger.debug("Probe failed for %s: %s", ip, exc)
        return None


async def _run_discovery_cycle() -> None:
    """Execute one full discovery sweep."""
    global _discovered_peers, _self_ip  # noqa: PLW0603

    # Resolve own Tailscale IP from the database (set by machine_info on startup)
    if not _self_ip:
        try:
            from agent.database import get_db

            db = await get_db()
            cursor = await db.execute(
                "SELECT tailscale_ip FROM machine_info WHERE id = 1"
            )
            row = await cursor.fetchone()
            if row and row[0]:
                _self_ip = row[0]
        except Exception:
            pass

    # Ask Tailscale CLI for all peers (runs in thread pool since it is blocking)
    loop = asyncio.get_running_loop()
    peer_ips = await loop.run_in_executor(None, _get_tailscale_peers)

    # Ensure self is always included
    all_ips = set(peer_ips)
    if _self_ip:
        all_ips.add(_self_ip)

    if not all_ips:
        return

    config = get_config()
    port = config.port

    # Probe all IPs concurrently
    async with httpx.AsyncClient() as client:
        tasks = [_probe_peer(client, ip, port, _self_ip) for ip in all_ips]
        results = await asyncio.gather(*tasks, return_exceptions=True)

    # Build new peer map
    new_peers: Dict[str, DiscoveredPeer] = {}
    for result in results:
        if isinstance(result, DiscoveredPeer):
            new_peers[result.tailscale_ip] = result

    # Grace period: keep peers that just went offline for one more cycle
    for ip, old_peer in _discovered_peers.items():
        if ip not in new_peers:
            if old_peer.status == "online":
                old_peer.status = "offline"
                new_peers[ip] = old_peer
            # Already offline from last cycle → drop it

    _discovered_peers = new_peers
    online = sum(1 for p in new_peers.values() if p.status == "online")
    logger.debug("Discovery: %d peers (%d online)", len(new_peers), online)


async def start_discovery_loop() -> None:
    """Background loop — call as ``asyncio.create_task()``."""
    # Short delay so the server and machine_info are ready
    await asyncio.sleep(5)

    # First sweep immediately
    try:
        await _run_discovery_cycle()
        online = sum(1 for p in _discovered_peers.values() if p.status == "online")
        logger.info("Peer discovery started — %d peer(s) found", online)
    except Exception as exc:
        logger.error("Initial discovery failed: %s", exc)

    # Then loop
    while True:
        try:
            await asyncio.sleep(DISCOVERY_INTERVAL)
            await _run_discovery_cycle()
        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.error("Discovery cycle error: %s", exc)
            await asyncio.sleep(10)


def get_discovered_peers() -> List[dict]:
    """Return the current list of discovered peers as plain dicts."""
    return [asdict(p) for p in _discovered_peers.values()]
