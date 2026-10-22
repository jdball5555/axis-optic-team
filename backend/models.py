"""Pydantic data models for the Axis Constraint Programming (CP-SAT) scheduler.

Validates input payloads sent from the Flutter client and serializes the
mathematically optimal schedule assignments returned by Google OR-Tools.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Input Models
# ---------------------------------------------------------------------------

class TimeWindowModel(BaseModel):
    """A continuous window of time defined by minutes from midnight (0 = 12:00 AM)."""
    start: int = Field(..., description="Start minute from midnight (e.g. 360 for 6:00 AM)")
    end: int = Field(..., description="End minute from midnight (e.g. 840 for 2:00 PM)")

    @property
    def minutes(self) -> int:
        return max(0, self.end - self.start)


class EmployeeModel(BaseModel):
    """Team member roster record."""
    id: str = Field(..., description="Unique employee user ID")
    name: str = Field(..., description="Full display name")
    title: str = Field(default="Team Member", description="Primary job title (e.g. Leader, Team Member)")
    tags: List[str] = Field(default_factory=list, description="Specialty tags (e.g. ['Truck', 'Prep', 'Trainer'])")
    designation: Optional[str] = Field(default=None, description="Designation such as 'Minor' or 'Adult'")
    is_minor: bool = Field(default=False, description="True if the employee is legally a minor")
    max_shifts_per_week: int = Field(default=5, ge=0, le=7, description="Hard cap on weekly shifts (left this week)")
    target_shifts: int = Field(default=5, ge=0, le=7, description="Target number of shifts to schedule")
    target_hours: float = Field(default=35.0, ge=0.0, description="Target weekly hours")
    day_night_preference: Optional[str] = Field(default=None, description="'Daytime' or 'Night' preference")
    can_train: bool = Field(default=False, description="True if authorized to be a trainer")


class SlotModel(BaseModel):
    """An individual shift requirement cut from a template row."""
    id: str = Field(..., description="Unique slot identifier (e.g. 'S1', 'S2')")
    date: str = Field(..., description="Target date in 'YYYY-MM-DD' format")
    day_index: int = Field(..., ge=0, le=6, description="0=Monday, 6=Sunday within the target week")
    row_id: str = Field(..., description="Template row ID that produced this slot")
    label: str = Field(default="", description="Human-readable row label (e.g. 'Leader', 'Prep', 'Truck')")
    start: int = Field(..., description="Start minute from midnight")
    end: int = Field(..., description="End minute from midnight")
    minutes: int = Field(..., description="Duration in minutes")
    allowed_titles: List[str] = Field(default_factory=list, description="Titles/tags allowed. Empty means open to anyone.")
    is_short: bool = Field(default=False, description="True if slot is short (< 3 hours) and can join a shift")

    @property
    def restricted(self) -> bool:
        return len(self.allowed_titles) > 0


class DayTemplateModel(BaseModel):
    """A day in the schedule containing its date, metadata, and required template slots."""
    date: str = Field(..., description="Date string 'YYYY-MM-DD'")
    day_index: int = Field(..., ge=0, le=6)
    weekday: int = Field(..., ge=1, le=7, description="1=Monday, 7=Sunday")
    template_id: Optional[str] = None
    template_name: Optional[str] = None
    slots: List[SlotModel] = Field(default_factory=list)


class AvailabilityModel(BaseModel):
    """An employee's available working hours by date."""
    employee_id: str
    # Map of date (YYYY-MM-DD) -> list of available windows.
    # If a date has an empty list, employee cannot work. If omitted, employee is open.
    day_windows: Dict[str, List[TimeWindowModel]] = Field(default_factory=dict)


class TimeOffModel(BaseModel):
    """Approved or requested time off."""
    employee_id: str
    date: str
    start: int = 0
    end: int = 1440
    approved: bool = True
    requested: bool = False


class BusyElsewhereModel(BaseModel):
    """Shifts the employee is already scheduled on another board/store."""
    employee_id: str
    date: str
    start: int
    end: int


class HistoryEntryModel(BaseModel):
    """Historical shift pattern to reward consistency."""
    employee_id: str
    weekday: int = Field(..., ge=1, le=7)
    start: int
    end: int
    frequency: float = Field(default=1.0, ge=0.0, le=1.0)


class TrainingStepModel(BaseModel):
    """A step in a trainee's training journey."""
    step_index: int
    with_trainer: bool = True
    position_id: Optional[str] = None


class TrainingPlanModel(BaseModel):
    """Trainee onboarding journey plan."""
    trainee_id: str
    steps: List[TrainingStepModel] = Field(default_factory=list)


class PinnedPairModel(BaseModel):
    """Explicit trainer + trainee pairing directive."""
    trainer_id: str
    trainee_id: str
    date: Optional[str] = None
    slot_id: Optional[str] = None
    source: str = "directive"


class MustWorkDirective(BaseModel):
    """Manager directive: employee must work on a date/slot."""
    employee_id: str
    date: str
    slot_id: Optional[str] = None
    window: Optional[TimeWindowModel] = None


class AdminTimeDirective(BaseModel):
    """Off-the-floor administrative time attached to a shift."""
    employee_id: str
    minutes: int = 60
    date: Optional[str] = None
    every_day: bool = False


class MeetingDirective(BaseModel):
    people: List[str]
    minutes: int = 60
    date: Optional[str] = None
    as_admin: bool = False


class DirectivesModel(BaseModel):
    """Manager overrides and custom instructions."""
    must_work: List[MustWorkDirective] = Field(default_factory=list)
    off: List[Dict[str, str]] = Field(default_factory=list, description="[{'employee_id': ..., 'date': ...}]")
    apart: List[List[str]] = Field(default_factory=list, description="Pairs of employee IDs who cannot work on same day")
    together: List[List[str]] = Field(default_factory=list, description="Groups of employee IDs who should work on same day")
    meetings: List[MeetingDirective] = Field(default_factory=list)
    keep: Dict[str, List[Dict[str, Any]]] = Field(default_factory=dict, description="employee_id -> [{'date': ..., 'start': ..., 'end': ...}]")
    max_shifts_override: Dict[str, int] = Field(default_factory=dict, description="employee_id -> max shifts")
    fixed_assignments: Dict[str, str] = Field(default_factory=dict, description="slot_id -> employee_id, placed by the client (requests, training); kept unless impossible")
    admin_requests: List[AdminTimeDirective] = Field(default_factory=list)


class RulesConfigModel(BaseModel):
    """Operational constraint rules and objective weights."""
    max_shifts_per_week: int = Field(default=5, ge=0, le=7)
    max_hours_per_day: float = Field(default=11.0, ge=1.0, le=16.0)
    min_rest_hours: float = Field(default=10.0, ge=0.0, le=24.0)
    max_consecutive_days: int = Field(default=6, ge=1, le=7)
    min_shift_hours: float = Field(default=3.0, ge=0.0, le=16.0)
    max_shift_hours: float = Field(default=9.0, ge=1.0, le=16.0)
    training_flow_enabled: bool = Field(default=True)
    
    # Minor labor regulations
    minor_max_daily_hours_school: float = Field(default=4.0)
    minor_max_daily_hours_weekend: float = Field(default=8.0)
    minor_curfew_school_night: int = Field(default=1140, description="19:00 = 7:00 PM cutoff on school nights")
    school_nights: List[int] = Field(default_factory=lambda: [7, 1, 2, 3, 4], description="Weekdays (1=Mon) that are school nights")

    # Preferences (the "try to" rules); off = not weighed
    usual_shifts: bool = True
    consistency: bool = True
    day_night: bool = True
    avoid_clopen: bool = True

    # Clopen boundaries
    clopen_close_end_min: int = Field(default=1260, description="21:00 = 9:00 PM closing cutoff")
    clopen_open_start_min: int = Field(default=420, description="07:00 = 7:00 AM opening cutoff")

    # Solver search limits
    solver_timeout_seconds: int = Field(default=30, ge=1, le=300)
    num_search_workers: int = Field(default=8, ge=1, le=32)


class SolveScheduleRequest(BaseModel):
    """Full input payload sent from the Axis Flutter client to the CP-SAT backend."""
    week_start: str = Field(..., description="Start of the week 'YYYY-MM-DD'")
    roster: List[EmployeeModel]
    days: List[DayTemplateModel]
    availabilities: List[AvailabilityModel] = Field(default_factory=list)
    time_off: List[TimeOffModel] = Field(default_factory=list)
    busy_elsewhere: List[BusyElsewhereModel] = Field(default_factory=list)
    history: List[HistoryEntryModel] = Field(default_factory=list)
    training_plans: List[TrainingPlanModel] = Field(default_factory=list)
    pinned_pairs: List[PinnedPairModel] = Field(default_factory=list)
    directives: DirectivesModel = Field(default_factory=DirectivesModel)
    training_only: List[str] = Field(default_factory=list, description="People in training: they work only their fixed (training) slots")
    trainees: Dict[str, str] = Field(default_factory=dict, description="slot_id -> trainee shadowing whoever works it")
    rules: RulesConfigModel = Field(default_factory=RulesConfigModel)


# ---------------------------------------------------------------------------
# Output Models
# ---------------------------------------------------------------------------

class ShiftPieceResponse(BaseModel):
    """One continuous slice of a shift occupying a specific template row."""
    id: str
    row_id: str
    start: int
    end: int
    admin: bool = False

    @property
    def minutes(self) -> int:
        return max(0, self.end - self.start)


class PositionSegmentResponse(BaseModel):
    """Position deployment segment on the shift page."""
    position_id: str
    start: int
    end: int


class ShiftResponse(BaseModel):
    """An employee's complete daily shift containing one or more contiguous pieces."""
    id: str
    user_id: str
    trainee_id: Optional[str] = None
    start: int
    end: int
    pieces: List[ShiftPieceResponse] = Field(default_factory=list)
    position_segments: List[PositionSegmentResponse] = Field(default_factory=list)


class ScheduleRowResponse(BaseModel):
    id: str
    label: str = ""
    windows: List[TimeWindowModel] = Field(default_factory=list)
    allowed_titles: List[str] = Field(default_factory=list)


class ScheduleDayResponse(BaseModel):
    """Complete solved day matching Flutter ScheduleDay model schema."""
    date: str
    template_id: Optional[str] = None
    template_name: Optional[str] = None
    rows: List[ScheduleRowResponse] = Field(default_factory=list)
    shifts: List[ShiftResponse] = Field(default_factory=list)
    labor_hours: float = 0.0


class EmployeeMetrics(BaseModel):
    shifts_scheduled: int
    total_hours: float
    target_shifts: int
    target_hours: float


class SolveScheduleMetrics(BaseModel):
    total_slots_needed: int
    total_slots_covered: int
    total_labor_hours: float
    employee_stats: Dict[str, EmployeeMetrics] = Field(default_factory=dict)


class OpenSlotResponse(BaseModel):
    """An unfilled slot requirement with diagnostics."""
    id: str
    date: str
    row_id: str
    label: str = ""
    start: int
    end: int
    minutes: int
    why: str = ""


class SolveScheduleResponse(BaseModel):
    """Full response returned to the Axis Flutter client."""
    status: str = Field(..., description="'OPTIMAL', 'FEASIBLE', or 'INFEASIBLE'")
    solve_time_seconds: float
    objective_value: Optional[float] = None
    days: List[ScheduleDayResponse] = Field(default_factory=list)
    open_slots: List[OpenSlotResponse] = Field(default_factory=list)
    metrics: Optional[SolveScheduleMetrics] = None
    infeasibility_reasons: List[str] = Field(default_factory=list)
    logs: List[str] = Field(default_factory=list)
