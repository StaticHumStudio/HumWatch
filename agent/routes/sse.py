"""Server-Sent Events endpoint for real-time metric streaming."""

import asyncio
import json
import logging

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

from agent.collector import subscribe, unsubscribe

logger = logging.getLogger("humwatch.routes.sse")

router = APIRouter()


@router.get("/sse")
async def sse_stream(request: Request):
    """SSE endpoint — streams metrics and process data every collection tick."""
    return StreamingResponse(
        _event_generator(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


async def _event_generator(request: Request):
    """Async generator that yields SSE events."""
    q = subscribe()

    try:
        heartbeat_interval = 30  # seconds
        while True:
            # Check if client disconnected
            if await request.is_disconnected():
                break

            try:
                # Wait for data with timeout (for heartbeat)
                data = await asyncio.wait_for(q.get(), timeout=heartbeat_interval)

                # Emit metrics event
                if "metrics" in data:
                    yield f"event: metrics\ndata: {json.dumps(data['metrics'])}\n\n"

                # Emit processes event
                if "processes" in data:
                    yield f"event: processes\ndata: {json.dumps(data['processes'])}\n\n"

            except asyncio.TimeoutError:
                # Send heartbeat comment to keep connection alive
                yield ": heartbeat\n\n"

    except (asyncio.CancelledError, GeneratorExit):
        pass
    finally:
        unsubscribe(q)
