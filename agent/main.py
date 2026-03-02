"""HumWatch agent entry point — FastAPI application."""

import asyncio
import logging
import time
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from agent import __version__
from agent.config import get_config, PROJECT_ROOT
from agent.database import init_db, close_db

logger = logging.getLogger("humwatch")

# Track server start time for uptime calculation
SERVER_START_TIME: float = 0.0


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan: startup and shutdown."""
    global SERVER_START_TIME
    SERVER_START_TIME = time.time()

    # Configure logging — console + file
    log_file = str(PROJECT_ROOT / "humwatch.log")
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(log_file, mode="w", encoding="utf-8"),
        ],
    )

    config = get_config()
    logger.info("HumWatch v%s starting on port %d", __version__, config.port)

    # Initialize database
    await init_db()

    # Import and start services (deferred to avoid circular imports)
    from agent.services.machine_info import update_machine_info
    from agent.services.retention import start_retention_loop
    from agent.collector import start_collector, stop_collector

    await update_machine_info()

    # Start background tasks
    retention_task = asyncio.create_task(start_retention_loop())
    await start_collector()

    logger.info("HumWatch ready at http://0.0.0.0:%d", config.port)

    yield

    # Shutdown
    logger.info("HumWatch shutting down...")
    await stop_collector()
    retention_task.cancel()
    try:
        await retention_task
    except asyncio.CancelledError:
        pass
    await close_db()
    logger.info("HumWatch stopped")


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title="HumWatch",
        version=__version__,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )

    # CORS — safe because only accessible on Tailnet
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET"],
        allow_headers=["*"],
    )

    # Import and include API routers
    from agent.routes.health import router as health_router
    from agent.routes.config_route import router as config_router
    from agent.routes.info import router as info_router
    from agent.routes.current import router as current_router
    from agent.routes.history import router as history_router
    from agent.routes.processes import router as processes_router
    from agent.routes.sse import router as sse_router

    app.include_router(health_router, prefix="/api")
    app.include_router(config_router, prefix="/api")
    app.include_router(info_router, prefix="/api")
    app.include_router(current_router, prefix="/api")
    app.include_router(history_router, prefix="/api")
    app.include_router(processes_router, prefix="/api")
    app.include_router(sse_router, prefix="/api")

    # Mount static files AFTER API routes so /api/* isn't shadowed
    static_dir = PROJECT_ROOT / "static"
    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")

    return app


app = create_app()


if __name__ == "__main__":
    config = get_config()
    uvicorn.run(
        "agent.main:app",
        host="0.0.0.0",
        port=config.port,
        log_level="info",
    )
