# Axis CP-SAT Constraint Programming Scheduling Service

This backend service provides mathematically optimal schedule generation for Axis using Google OR-Tools CP-SAT wrapped in a FastAPI REST service. It replaces the old greedy heuristic and LLM repair loops with an exact mathematical solver.

---

## 1. Quick Start

### Local Setup
Ensure Python 3.10+ is installed:
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Run Server
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
Interactive API docs are available at: [http://localhost:8000/docs](http://localhost:8000/docs)

### Docker Setup
```bash
docker build -t axis-scheduler .
docker run -p 8000:8000 axis-scheduler
```

---

## 2. API Endpoints

### `GET /health`
Returns service status and solver engine details.

### `POST /solve_schedule`
Accepts a `SolveScheduleRequest` JSON payload and returns the optimal `SolveScheduleResponse`.

**Request Structure:**
- `week_start`: `"YYYY-MM-DD"`
- `roster`: List of employees (ID, title, tags, minor designation, shift caps, preferences)
- `days`: List of days, each with template slots (start, end, row ID, required titles/tags)
- `availabilities`: Employee availability windows by date
- `time_off`: Approved or requested time off
- `busy_elsewhere`: Other schedule commitments
- `history`: Historic shift habits for consistency scoring
- `training_plans`: New hire onboarding journeys
- `pinned_pairs`: Trainer + Trainee pairings
- `directives`: Manager overrides (Must Work, Off, Apart, Max Shifts)
- `rules`: Operational parameters (max hours/day, rest gap, curfew, etc.)

**How the app uses it:** the Flutter client places the manager's requests (must-work days,
meetings) and training shifts itself, sends them as `fixed_assignments` (kept unless impossible;
they override availability), lists people in training in `training_only` (they work only their
training slots) and trainee pairings in `trainees`. Admin time is added by the client after
solving, joined onto each finished shift. Rules between days (rest, clopens, days in a row) use
real calendar dates, so a day without a template breaks a run. The objective covers the most
template *minutes* first. The client also runs its local algorithm (which can split a slot
between two people) and keeps whichever schedule covers more.

The website (team.axisoptic.com) only uses this service if it's hosted somewhere public and the
site is built with `--dart-define=SCHEDULE_BACKEND_URL=https://…`; otherwise it uses the local
algorithm.

**Response Structure:**
- `status`: `"OPTIMAL"`, `"FEASIBLE"`, or `"INFEASIBLE"`
- `solve_time_seconds`: Duration of solve in seconds
- `objective_value`: Minimized penalty score
- `days`: Full list of `ScheduleDay` objects with exact `Shift` and `ShiftPiece` records
- `metrics`: Labor hours, slots filled, shift counts
- `infeasibility_reasons`: Diagnostic explanations if no feasible schedule exists
