"""Peer discovery endpoint — returns HumWatch instances found on the network."""

from fastapi import APIRouter

from agent.services.discovery import get_discovered_peers

router = APIRouter()


@router.get("/peers")
async def get_peers():
    """Return discovered HumWatch peers."""
    return get_discovered_peers()
