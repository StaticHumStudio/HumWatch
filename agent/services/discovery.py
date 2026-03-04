"""Peer discovery — find other HumWatch instances on the network.

Strategies run in parallel each cycle:
  1. Tailscale CLI  (if installed)
  2. ZeroTier CLI   (if installed)
  3. Subnet scan    (always available — probes /24 around own IP)
"""

import asyncio
import ipaddress
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
SUBNET_TCP_TIMEOUT = 0.5 # seconds per TCP connect probe
SUBNET_CONCURRENCY = 50  # max simultaneous TCP probes


@dataclass
class DiscoveredPeer:
    url: str
    network_ip: str
    hostname: str
    os_version: str
    cpu_name: str
    gpu_name: str
    total_ram_mb: int
    agent_version: str
    status: str            # "online" | "offline"
    last_seen: str         # ISO 8601 UTC
    is_self: bool
    discovery_source: str  # "tailscale" | "zerotier" | "subnet_scan" | "local"


# Module-level state
_discovered_peers: Dict[str, DiscoveredPeer] = {}
_self_ip: str = ""


# ---------------------------------------------------------------------------
#  Strategy 1: Tailscale CLI
# ---------------------------------------------------------------------------

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
        logger.debug("Tailscale CLI not found — skipping strategy")
        return []
    except subprocess.TimeoutExpired:
        logger.warning("tailscale status timed out")
        return []
    except (json.JSONDecodeError, KeyError) as exc:
        logger.warning("Failed to parse tailscale status: %s", exc)
        return []
    except Exception as exc:
        logger.debug("Tailscale strategy error: %s", exc)
        return []


# ---------------------------------------------------------------------------
#  Strategy 2: ZeroTier CLI
# ---------------------------------------------------------------------------

def _get_zerotier_peers() -> List[str]:
    """Run ``zerotier-cli listpeers -j`` and extract IPv4 addresses."""
    try:
        result = subprocess.run(
            ["zerotier-cli", "listpeers", "-j"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return []

        data = json.loads(result.stdout)
        ips: List[str] = []
        for peer in data:
            paths = peer.get("paths", [])
            for path in paths:
                addr = path.get("address", "")
                # Format: "ip/port"
                if "/" in addr:
                    ip = addr.split("/")[0]
                    if ":" not in ip:  # IPv4 only
                        ips.append(ip)
                        break
        return ips

    except FileNotFoundError:
        logger.debug("ZeroTier CLI not found — skipping strategy")
        return []
    except subprocess.TimeoutExpired:
        logger.warning("zerotier-cli timed out")
        return []
    except (json.JSONDecodeError, KeyError) as exc:
        logger.warning("Failed to parse zerotier-cli output: %s", exc)
        return []
    except Exception as exc:
        logger.debug("ZeroTier strategy error: %s", exc)
        return []


# ---------------------------------------------------------------------------
#  Strategy 3: Subnet scan
# ---------------------------------------------------------------------------

async def _get_subnet_peers(self_ip: str, port: int) -> List[str]:
    """Probe the /24 subnet around *self_ip* for open HumWatch ports."""
    if not self_ip:
        return []

    try:
        network = ipaddress.ip_network(f"{self_ip}/24", strict=False)
    except ValueError:
        return []

    self_ip_obj = ipaddress.ip_address(self_ip)
    candidates = [str(ip) for ip in network.hosts() if ip != self_ip_obj]

    sem = asyncio.Semaphore(SUBNET_CONCURRENCY)

    async def _tcp_probe(ip: str) -> Optional[str]:
        async with sem:
            try:
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection(ip, port),
                    timeout=SUBNET_TCP_TIMEOUT,
                )
                writer.close()
                await writer.wait_closed()
                return ip
            except (asyncio.TimeoutError, ConnectionRefusedError, OSError):
                return None

    results = await asyncio.gather(
        *[_tcp_probe(ip) for ip in candidates],
        return_exceptions=True,
    )
    return [r for r in results if isinstance(r, str)]


# ---------------------------------------------------------------------------
#  HTTP peer probe (shared by all strategies)
# ---------------------------------------------------------------------------

async def _probe_peer(
    client: httpx.AsyncClient,
    ip: str,
    port: int,
    self_ip: str,
    source: str,
) -> Optional[DiscoveredPeer]:
    """Probe a single IP for a running HumWatch instance."""
    base_url = f"http://{ip}:{port}"
    now = datetime.now(timezone.utc).isoformat()

    try:
        resp = await client.get(f"{base_url}/api/health", timeout=PROBE_TIMEOUT)
        if resp.status_code != 200:
            return None
        health = resp.json()
        if health.get("status") != "ok":
            return None

        version = health.get("version", "")
        try:
            info_resp = await client.get(f"{base_url}/api/info", timeout=PROBE_TIMEOUT)
            info = info_resp.json() if info_resp.status_code == 200 else {}
        except Exception:
            info = {}

        return DiscoveredPeer(
            url=base_url,
            network_ip=ip,
            hostname=info.get("hostname", ip),
            os_version=info.get("os_version", ""),
            cpu_name=info.get("cpu_name", ""),
            gpu_name=info.get("gpu_name", ""),
            total_ram_mb=info.get("total_ram_mb", 0),
            agent_version=info.get("agent_version", version),
            status="online",
            last_seen=now,
            is_self=(ip == self_ip),
            discovery_source=source,
        )

    except (httpx.TimeoutException, httpx.ConnectError, httpx.HTTPError):
        return None
    except Exception as exc:
        logger.debug("Probe failed for %s: %s", ip, exc)
        return None


# ---------------------------------------------------------------------------
#  Discovery cycle — runs all strategies, merges, probes
# ---------------------------------------------------------------------------

async def _run_discovery_cycle() -> None:
    """Execute one full discovery sweep using all available strategies."""
    global _discovered_peers, _self_ip  # noqa: PLW0603

    # Resolve own network IP from the database (set by machine_info on startup)
    if not _self_ip:
        try:
            from agent.database import get_db

            db = await get_db()
            cursor = await db.execute(
                "SELECT network_ip FROM machine_info WHERE id = 1"
            )
            row = await cursor.fetchone()
            if row and row[0]:
                _self_ip = row[0]
        except Exception:
            pass

    config = get_config()
    port = config.port
    loop = asyncio.get_running_loop()

    # Run all strategies concurrently
    ts_future = loop.run_in_executor(None, _get_tailscale_peers)
    zt_future = loop.run_in_executor(None, _get_zerotier_peers)
    subnet_future = _get_subnet_peers(_self_ip, port)

    results = await asyncio.gather(
        ts_future, zt_future, subnet_future,
        return_exceptions=True,
    )

    ts_ips = results[0] if isinstance(results[0], list) else []
    zt_ips = results[1] if isinstance(results[1], list) else []
    subnet_ips = results[2] if isinstance(results[2], list) else []

    # Track discovery source per IP (first source wins)
    ip_sources: Dict[str, str] = {}
    for ip in ts_ips:
        ip_sources[ip] = "tailscale"
    for ip in zt_ips:
        ip_sources.setdefault(ip, "zerotier")
    for ip in subnet_ips:
        ip_sources.setdefault(ip, "subnet_scan")

    # Ensure self is included
    all_ips = set(ip_sources.keys())
    if _self_ip:
        all_ips.add(_self_ip)
        ip_sources.setdefault(_self_ip, "local")

    if not all_ips:
        return

    # Probe all IPs concurrently via HTTP
    async with httpx.AsyncClient() as client:
        tasks = [
            _probe_peer(client, ip, port, _self_ip, ip_sources.get(ip, "subnet_scan"))
            for ip in all_ips
        ]
        probe_results = await asyncio.gather(*tasks, return_exceptions=True)

    # Build new peer map
    new_peers: Dict[str, DiscoveredPeer] = {}
    for result in probe_results:
        if isinstance(result, DiscoveredPeer):
            new_peers[result.network_ip] = result

    # Grace period: keep peers that just went offline for one more cycle
    for ip, old_peer in _discovered_peers.items():
        if ip not in new_peers:
            if old_peer.status == "online":
                old_peer.status = "offline"
                new_peers[ip] = old_peer
            # Already offline from last cycle → drop it

    _discovered_peers = new_peers
    online = sum(1 for p in new_peers.values() if p.status == "online")
    logger.debug(
        "Discovery: %d peers (%d online) [tailscale=%d, zerotier=%d, subnet=%d]",
        len(new_peers), online, len(ts_ips), len(zt_ips), len(subnet_ips),
    )


# ---------------------------------------------------------------------------
#  Background loop
# ---------------------------------------------------------------------------

async def start_discovery_loop() -> None:
    """Background loop — call as ``asyncio.create_task()``."""
    await asyncio.sleep(5)

    try:
        await _run_discovery_cycle()
        online = sum(1 for p in _discovered_peers.values() if p.status == "online")
        logger.info("Peer discovery started — %d peer(s) found", online)
    except Exception as exc:
        logger.error("Initial discovery failed: %s", exc)

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
