"""FastAPI service exposing the Axis Constraint Programming (CP-SAT) scheduling engine.

Accepts weekly restaurant templates, employee rosters, availability, time-off,
and manager directives over HTTP POST, and returns the mathematically optimal schedule.
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from models import SolveScheduleRequest, SolveScheduleResponse
from solver import AxisScheduleSolver

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("axis_scheduler")

app = FastAPI(
    title="Axis CP-SAT Scheduler Service",
    description="Constraint Programming schedule optimization backend for Axis Team using Google OR-Tools.",
    version="1.0.0",
)

# Enable CORS for Flutter web, mobile, and desktop clients
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r".*",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", status_code=status.HTTP_200_OK)
async def health_check() -> Dict[str, Any]:
    """Health check endpoint to verify backend service status and solver availability."""
    return {
        "status": "healthy",
        "service": "axis_cp_sat_scheduler",
        "solver": "Google OR-Tools CP-SAT",
        "timestamp": time.time(),
    }


@app.post(
    "/solve_schedule",
    response_model=SolveScheduleResponse,
    status_code=status.HTTP_200_OK,
    summary="Solve Weekly Restaurant Schedule",
    description="Formulates and solves the mathematical optimization model for the requested schedule week.",
)
async def solve_schedule(request: SolveScheduleRequest) -> SolveScheduleResponse:
    """Receives the weekly template and employee roster, executes CP-SAT, and returns optimal shifts."""
    logger.info(
        "Received /solve_schedule request for week %s (roster=%d, days=%d)",
        request.week_start,
        len(request.roster),
        len(request.days),
    )

    try:
        solver = AxisScheduleSolver(request)
        response = solver.solve()

        logger.info(
            "Schedule solve finished in %.2fs with status=%s",
            response.solve_time_seconds,
            response.status,
        )

        if response.status == "INFEASIBLE":
            logger.warning("Schedule is INFEASIBLE: %s", response.infeasibility_reasons)

        return response

    except Exception as exc:
        logger.exception("Unexpected error during schedule solving: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Solver execution failed: {str(exc)}",
        ) from exc


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
