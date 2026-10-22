"""Google OR-Tools (CP-SAT) mathematical solver for the Axis scheduling engine.

Formulates and solves the restaurant weekly scheduling problem as an exact Constraint
Programming (CP) optimization model. Replaces heuristic/greedy rules and LLM repair loops
with guaranteed mathematical feasibility and globally optimal shift assignments.
"""

from __future__ import annotations

import time
from datetime import date as _date
from typing import Dict, List, Optional, Tuple
from ortools.sat.python import cp_model

from models import (
    DayTemplateModel,
    EmployeeMetrics,
    EmployeeModel,
    HistoryEntryModel,
    OpenSlotResponse,
    ScheduleDayResponse,
    ScheduleRowResponse,
    ShiftPieceResponse,
    ShiftResponse,
    SlotModel,
    SolveScheduleMetrics,
    SolveScheduleRequest,
    SolveScheduleResponse,
    TimeWindowModel,
)


class AxisScheduleSolver:
    """Encapsulates the CP-SAT model building, solving, and solution parsing for Axis."""

    def __init__(self, request: SolveScheduleRequest):
        self.request = request
        self.rules = request.rules
        self.roster = request.roster
        self.days = request.days
        self.employees_by_id: Dict[str, EmployeeModel] = {e.id: e for e in self.roster}

        # Slots the client already placed (manager requests, training): slot_id -> employee_id.
        # They are kept unless that's impossible, and override availability / titles.
        self.fixed: Dict[str, str] = dict(request.directives.fixed_assignments)

        # Calendar day number per date, so rules between days use real dates
        # (the days being built may skip some, e.g. no template on Wednesday).
        self.day_ordinal: Dict[str, int] = {d.date: _date.fromisoformat(d.date).toordinal() for d in self.days}

        # Model and variables
        self.model = cp_model.CpModel()
        self.solver = cp_model.CpSolver()
        self.work: Dict[Tuple[str, str, str], cp_model.IntVar] = {}  # (e_id, date, slot_id) -> BoolVar
        self.worked_day: Dict[Tuple[str, str], cp_model.IntVar] = {}  # (e_id, date) -> BoolVar
        self.daily_minutes: Dict[Tuple[str, str], cp_model.IntVar] = {}  # (e_id, date) -> IntVar
        self.is_shift_start: Dict[Tuple[str, str], cp_model.IntVar] = {}  # (e_id, slot_id) -> BoolVar
        self.total_shifts: Dict[str, cp_model.IntVar] = {}  # e_id -> IntVar
        
        # Training shift attachments: slot_id -> trainee_id (placed by the client),
        # and pinned pairs placed here: slot_id -> (BoolVar, trainee_id).
        self.trainee_on_slot: Dict[str, str] = dict(request.trainees)
        self.pair_on_slot: Dict[str, Tuple[cp_model.IntVar, str]] = {}

        # Unassigned slot indicators for template coverage slack
        self.unassigned: Dict[str, cp_model.IntVar] = {}  # slot_id -> BoolVar
        self.directive_penalties: List[cp_model.LinearExpr] = []

        # Diagnostic trackers
        self.logs: List[str] = []
        self.infeasibility_reasons: List[str] = []

    def solve(self) -> SolveScheduleResponse:
        """Builds constraints, executes the CP-SAT solver, and constructs the response."""
        start_time = time.time()
        self.logs.append(f"Starting Axis CP-SAT solver for week of {self.request.week_start}...")
        self.logs.append(f"Roster size: {len(self.roster)}, Schedule days: {len(self.days)}")

        # Step 1: Pre-process and validate
        total_slots = sum(len(d.slots) for d in self.days)
        self.logs.append(f"Total template slots to fill: {total_slots}")
        if total_slots == 0:
            return SolveScheduleResponse(
                status="OPTIMAL",
                solve_time_seconds=time.time() - start_time,
                objective_value=0.0,
                days=[
                    ScheduleDayResponse(
                        date=d.date,
                        template_id=d.template_id,
                        template_name=d.template_name,
                        rows=[],
                        shifts=[],
                        labor_hours=0.0,
                    )
                    for d in self.days
                ],
                metrics=SolveScheduleMetrics(
                    total_slots_needed=0,
                    total_slots_covered=0,
                    total_labor_hours=0.0,
                ),
                logs=["No template slots required this week."],
            )

        # Step 2: Build variables and all constraints
        self._create_decision_variables()
        self._apply_hard_constraints()
        self._apply_soft_constraints_and_objective()

        # Step 3: Configure CP-SAT solver parameters
        self.solver.parameters.max_time_in_seconds = float(self.rules.solver_timeout_seconds)
        self.solver.parameters.num_search_workers = int(self.rules.num_search_workers)
        self.solver.parameters.log_search_progress = False

        # Step 4: Run the solver
        solve_status = self.solver.Solve(self.model)
        solve_time = time.time() - start_time
        status_name = self.solver.StatusName(solve_status)
        self.logs.append(f"Solver completed in {solve_time:.2f}s with status: {status_name}")

        if solve_status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            return self._build_solution_response(status_name, solve_time)
        else:
            self._diagnose_infeasibility()
            return SolveScheduleResponse(
                status="INFEASIBLE",
                solve_time_seconds=solve_time,
                objective_value=None,
                days=[],
                open_slots=[],
                metrics=None,
                infeasibility_reasons=self.infeasibility_reasons,
                logs=self.logs,
            )

    # -----------------------------------------------------------------------
    # Decision Variables
    # -----------------------------------------------------------------------

    def _create_decision_variables(self):
        """Creates boolean assignment variables work[(e, d, s)] and helper tracking variables."""
        for day in self.days:
            d = day.date
            for slot in day.slots:
                s = slot.id
                self.unassigned[s] = self.model.NewBoolVar(f"unassigned_{s}")
                for emp in self.roster:
                    e = emp.id
                    var_name = f"work_{e}_{d}_{s}"
                    self.work[(e, d, s)] = self.model.NewBoolVar(var_name)

            for emp in self.roster:
                e = emp.id
                # Boolean indicator: Did employee e work on day d?
                self.worked_day[(e, d)] = self.model.NewBoolVar(f"worked_{e}_{d}")
                
                # Integer total minutes worked on day d
                self.daily_minutes[(e, d)] = self.model.NewIntVar(0, 1440, f"min_{e}_{d}")

                # Link daily_minutes to slot assignments
                day_slots = day.slots
                self.model.Add(
                    self.daily_minutes[(e, d)]
                    == sum(self.work[(e, d, sl.id)] * sl.minutes for sl in day_slots)
                )

                # Link worked_day to slot assignments
                # worked_day == 1 if and only if sum(work) >= 1
                if day_slots:
                    slot_vars = [self.work[(e, d, sl.id)] for sl in day_slots]
                    self.model.AddMaxEquality(self.worked_day[(e, d)], slot_vars)
                else:
                    self.model.Add(self.worked_day[(e, d)] == 0)

        # Weekly shifts per employee
        for emp in self.roster:
            e = emp.id
            self.total_shifts[e] = self.model.NewIntVar(0, 7, f"shifts_{e}")
            self.model.Add(
                self.total_shifts[e] == sum(self.worked_day[(e, day.date)] for day in self.days)
            )

    # -----------------------------------------------------------------------
    # Hard Constraints (model.Add())
    # -----------------------------------------------------------------------

    def _apply_hard_constraints(self):
        """Enforces all mandatory operational constraints."""
        self._constraint_template_coverage()
        self._constraint_availability_and_time_off()
        self._constraint_roles_and_tags()
        self._constraint_training_only()
        self._constraint_one_continuous_shift()
        self._constraint_maximum_hours_and_shifts()
        self._constraint_rest_periods()
        self._constraint_consecutive_days()
        self._constraint_minor_regulations()
        self._constraint_training_and_directives()

    def _constraint_template_coverage(self):
        """Rule 1: Template Coverage - every slot must either be covered or marked unassigned."""
        for day in self.days:
            d = day.date
            for slot in day.slots:
                s = slot.id
                self.model.Add(
                    sum(self.work[(emp.id, d, s)] for emp in self.roster) + self.unassigned[s] == 1
                )

    def _constraint_availability_and_time_off(self):
        """Rule 2: Availability & Time Off - hard zero assignment if employee cannot work."""
        # Index time off by (emp_id, date)
        time_off_by_emp: Dict[Tuple[str, str], List[Tuple[int, int]]] = {}
        for to in self.request.time_off:
            time_off_by_emp.setdefault((to.employee_id, to.date), []).append((to.start, to.end))

        # Index busy elsewhere by (emp_id, date)
        busy_by_emp: Dict[Tuple[str, str], List[Tuple[int, int]]] = {}
        for b in self.request.busy_elsewhere:
            busy_by_emp.setdefault((b.employee_id, b.date), []).append((b.start, b.end))

        # Index availability by (emp_id, date)
        avail_by_emp: Dict[Tuple[str, str], List[TimeWindowModel]] = {}
        for a in self.request.availabilities:
            for date_key, windows in a.day_windows.items():
                avail_by_emp[(a.employee_id, date_key)] = windows

        for day in self.days:
            d = day.date
            for slot in day.slots:
                s = slot.id
                for emp in self.roster:
                    e = emp.id
                    blocked = False

                    # Check explicit availability windows for this date
                    if (e, d) in avail_by_emp:
                        windows = avail_by_emp[(e, d)]
                        if not windows:
                            # Empty list means completely unavailable on this day
                            blocked = True
                        else:
                            # Must be fully contained in at least one available window
                            contained = any(w.start <= slot.start and slot.end <= w.end for w in windows)
                            if not contained:
                                blocked = True

                    # Check time off (approved or requested)
                    if not blocked and (e, d) in time_off_by_emp:
                        for to_start, to_end in time_off_by_emp[(e, d)]:
                            # Overlaps if slot.start < to_end and to_start < slot.end
                            if slot.start < to_end and to_start < slot.end:
                                blocked = True
                                break

                    # Check busy elsewhere on another schedule
                    if not blocked and (e, d) in busy_by_emp:
                        for b_start, b_end in busy_by_emp[(e, d)]:
                            if slot.start < b_end and b_start < slot.end:
                                blocked = True
                                break

                    if blocked and self.fixed.get(s) != e:
                        self.model.Add(self.work[(e, d, s)] == 0)

    def _constraint_roles_and_tags(self):
        """Rule 3: Roles & Tags - only employees with matching title or tag can work restricted slots."""
        for day in self.days:
            d = day.date
            for slot in day.slots:
                s = slot.id
                if not slot.restricted:
                    continue
                allowed_set = set(slot.allowed_titles)
                for emp in self.roster:
                    e = emp.id
                    emp_titles_and_tags = {emp.title} | set(emp.tags)
                    # Check if there is any intersection
                    if allowed_set.isdisjoint(emp_titles_and_tags) and self.fixed.get(s) != e:
                        self.model.Add(self.work[(e, d, s)] == 0)

    def _constraint_training_only(self):
        """Rule 3b: People in training work only the slots placed for them (their training
        shifts), and a trainee shadowing someone works nothing else that day."""
        training_only = {e for e in self.request.training_only if e in self.employees_by_id}
        shadow_days = {
            (t, sl.date): s_id
            for s_id, t in self.trainee_on_slot.items()
            for sl in self._all_slots()
            if sl.id == s_id and t in self.employees_by_id
        }
        for day in self.days:
            d = day.date
            for slot in day.slots:
                for e in training_only:
                    if self.fixed.get(slot.id) != e:
                        self.model.Add(self.work[(e, d, slot.id)] == 0)
                for (t, sd), _ in shadow_days.items():
                    if sd == d and self.fixed.get(slot.id) != t:
                        self.model.Add(self.work[(t, d, slot.id)] == 0)

    def _constraint_one_continuous_shift(self):
        """Rule 4: One Continuous Shift - split shifts are strictly forbidden.
        
        Mathematical formulation:
        1. Two slots on the same day that overlap in time cannot both be assigned to employee e.
        2. A continuous shift has exactly ONE shift-start. A slot s is a shift-start for e if e
           works s and does not work any immediately preceding adjacent slot p (where p.end == s.start).
           Sum of shift-starts on day d must equal worked_day[(e, d)].
        """
        for day in self.days:
            d = day.date
            day_slots = day.slots

            # 4a. Mutex on overlapping slots
            n_slots = len(day_slots)
            for i in range(n_slots):
                s1 = day_slots[i]
                for j in range(i + 1, n_slots):
                    s2 = day_slots[j]
                    if s1.start < s2.end and s2.start < s1.end:
                        for emp in self.roster:
                            e = emp.id
                            self.model.Add(self.work[(e, d, s1.id)] + self.work[(e, d, s2.id)] <= 1)

            # 4b. Single contiguous shift per day (No split shifts)
            for emp in self.roster:
                e = emp.id
                day_start_indicators = []
                for s in day_slots:
                    # Find all preceding slots in the day whose end touches this slot's start
                    preceding = [p for p in day_slots if p.end == s.start]
                    is_start_var = self.model.NewBoolVar(f"start_{e}_{d}_{s.id}")
                    self.is_shift_start[(e, s.id)] = is_start_var

                    if not preceding:
                        # No preceding touching slot exists in the template:
                        # If e works s, s is definitely the start of e's shift block
                        self.model.Add(is_start_var == self.work[(e, d, s.id)])
                    else:
                        # Preceding slots exist: is_start >= work[s] - sum(work[p])
                        self.model.Add(
                            is_start_var >= self.work[(e, d, s.id)] - sum(self.work[(e, d, p.id)] for p in preceding)
                        )
                        # And is_start <= work[s]
                        self.model.Add(is_start_var <= self.work[(e, d, s.id)])
                    day_start_indicators.append(is_start_var)

                # Total shift starts on day d must equal worked_day[(e, d)]
                # If worked_day == 1, there is exactly 1 contiguous block! If 0, exactly 0.
                if day_start_indicators:
                    self.model.Add(sum(day_start_indicators) == self.worked_day[(e, d)])

    def _constraint_maximum_hours_and_shifts(self):
        """Rule 5: Maximum Hours/Shifts - weekly shift caps and global daily hour cap."""
        max_daily_minutes = int(self.rules.max_hours_per_day * 60)
        overridden_max_shifts = self.request.directives.max_shifts_override

        for emp in self.roster:
            e = emp.id
            # Weekly shifts cap (respecting directives override if present)
            max_shifts = overridden_max_shifts.get(e, emp.max_shifts_per_week)
            self.model.Add(self.total_shifts[e] <= max_shifts)

            # Daily hours cap
            for day in self.days:
                d = day.date
                self.model.Add(self.daily_minutes[(e, d)] <= max_daily_minutes)

    def _constraint_rest_periods(self):
        """Rule 6: Rest Periods - minimum gap between shifts on calendar-consecutive days.
        
        If employee e works slot s1 on day d and slot s2 on day d+1, and the rest between
        s1.end and s2.start is less than min_rest_hours, e cannot work both.
        """
        if self.rules.min_rest_hours <= 0:
            return

        min_rest_minutes = int(self.rules.min_rest_hours * 60)

        for day1, day2 in self._next_day_pairs():
            d1 = day1.date
            d2 = day2.date

            for s1 in day1.slots:
                for s2 in day2.slots:
                    # Time between end of s1 and start of s2:
                    # (1440 - s1.end) on day 1 + s2.start on day 2
                    rest_gap = (1440 - s1.end) + s2.start
                    if rest_gap < min_rest_minutes:
                        for emp in self.roster:
                            e = emp.id
                            self.model.Add(self.work[(e, d1, s1.id)] + self.work[(e, d2, s2.id)] <= 1)

    def _constraint_consecutive_days(self):
        """Rule 7: Consecutive Days - cap the days worked in a row (calendar days)."""
        max_consec = self.rules.max_consecutive_days
        window_size = max_consec + 1
        by_ordinal = {o: d for d, o in self.day_ordinal.items()}

        for first in sorted(by_ordinal):
            # Only runs of real consecutive dates count (a day not being built breaks the run).
            window_days = [by_ordinal.get(first + j) for j in range(window_size)]
            if any(wd is None for wd in window_days):
                continue
            for emp in self.roster:
                e = emp.id
                self.model.Add(
                    sum(self.worked_day[(e, d)] for d in window_days) <= max_consec
                )

    def _constraint_minor_regulations(self):
        """Rule 8: Minor Regulations - strict daily hour caps and school night curfew."""
        school_night_max_min = int(self.rules.minor_max_daily_hours_school * 60)
        weekend_max_min = int(self.rules.minor_max_daily_hours_weekend * 60)
        curfew = self.rules.minor_curfew_school_night

        for day in self.days:
            d = day.date
            # Weekdays: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
            # School nights in restaurant operations are Sunday through Thursday
            is_school_night = day.weekday in self.rules.school_nights
            daily_minor_limit = school_night_max_min if is_school_night else weekend_max_min

            for emp in self.roster:
                if not emp.is_minor:
                    continue
                e = emp.id

                # Daily hour cap for minor
                self.model.Add(self.daily_minutes[(e, d)] <= daily_minor_limit)

                # Curfew cutoff on school nights: cannot work any slot ending after curfew
                if is_school_night:
                    for slot in day.slots:
                        if slot.end > curfew:
                            self.model.Add(self.work[(e, d, slot.id)] == 0)

    def _constraint_training_and_directives(self):
        """Rule 9: Training Flow & Manager Directives - pinned pairings and manual overrides."""
        directives = self.request.directives

        # 9a. Pinned Trainer + Trainee pairings
        for pair_idx, pair in enumerate(self.request.pinned_pairs):
            trainer_id = pair.trainer_id
            trainee_id = pair.trainee_id
            target_date = pair.date

            trainer = self.employees_by_id.get(trainer_id)
            trainee = self.employees_by_id.get(trainee_id)
            if not trainer or not trainee:
                continue

            # Candidate slots where trainer is qualified to work
            candidate_slots: List[Tuple[str, SlotModel]] = []
            for day in self.days:
                if target_date and day.date != target_date:
                    continue
                d = day.date
                for slot in day.slots:
                    if pair.slot_id and slot.id != pair.slot_id:
                        continue
                    if not pair.slot_id and slot.is_short:
                        continue
                    # Check trainer qualification
                    if slot.restricted and set(slot.allowed_titles).isdisjoint({trainer.title} | set(trainer.tags)):
                        continue
                    candidate_slots.append((d, slot))

            if candidate_slots:
                # Exactly one chosen slot (or none, with a penalty) where the trainer works
                # and the trainee shadows; only that shift gets the trainee.
                pair_vars = []
                for d, slot in candidate_slots:
                    on = self.model.NewBoolVar(f"pair_{pair_idx}_{slot.id}")
                    self.model.Add(on <= self.work[(trainer_id, d, slot.id)])
                    self.pair_on_slot[slot.id] = (on, trainee_id)
                    pair_vars.append(on)
                    # Trainee shadows the trainer: no slot of their own that day
                    for other_s in self._slots_for_date(d):
                        self.model.Add(self.work[(trainee_id, d, other_s.id)] <= 1 - on)
                pair_placed = self.model.NewBoolVar(f"pair_placed_{pair_idx}")
                self.model.Add(sum(pair_vars) == pair_placed)
                self.directive_penalties.append((1 - pair_placed) * 40000)

        # 9b. Training plans (when training flow enabled)
        if self.rules.training_flow_enabled:
            for plan_idx, plan in enumerate(self.request.training_plans):
                t_id = plan.trainee_id
                trainee = self.employees_by_id.get(t_id)
                if not trainee:
                    continue
                for step_idx, step in enumerate(plan.steps):
                    if not step.with_trainer and step.position_id:
                        # Solo training: find candidate slots matching position_id
                        candidate_solo_slots: List[Tuple[str, SlotModel]] = []
                        for day in self.days:
                            for slot in day.slots:
                                if step.position_id in slot.allowed_titles or not slot.restricted:
                                    candidate_solo_slots.append((day.date, slot))
                        if candidate_solo_slots:
                            step_placed = self.model.NewBoolVar(f"train_solo_{plan_idx}_{step_idx}")
                            self.model.Add(
                                sum(self.work[(t_id, d, s.id)] for d, s in candidate_solo_slots) >= step_placed
                            )
                            self.directive_penalties.append((1 - step_placed) * 30000)

        # 9c. Directives: Fixed assignments
        for slot_id, emp_id in directives.fixed_assignments.items():
            for day in self.days:
                for slot in day.slots:
                    if slot.id == slot_id and (emp_id, day.date, slot_id) in self.work:
                        # Kept unless another hard rule makes it impossible.
                        fix_var = self.model.NewBoolVar(f"fix_{emp_id}_{slot_id}")
                        self.model.Add(self.work[(emp_id, day.date, slot_id)] == fix_var)
                        self.directive_penalties.append((1 - fix_var) * 1_000_000)

        # 9d. Directives: Must work
        for mw_idx, mw in enumerate(directives.must_work):
            e = mw.employee_id
            d = mw.date
            if (e, d) in self.worked_day:
                mw_placed = self.model.NewBoolVar(f"mw_{mw_idx}_{e}_{d}")
                if mw.slot_id and (e, d, mw.slot_id) in self.work:
                    self.model.Add(self.work[(e, d, mw.slot_id)] == mw_placed)
                else:
                    self.model.Add(self.worked_day[(e, d)] == mw_placed)
                self.directive_penalties.append((1 - mw_placed) * 35000)

        # 9e. Directives: Off
        for off_req in directives.off:
            e = off_req.get("employee_id")
            d = off_req.get("date")
            if e and d and (e, d) in self.worked_day:
                self.model.Add(self.worked_day[(e, d)] == 0)

        # 9f. Directives: Apart pairs (cannot work on the same day)
        for apart_pair in directives.apart:
            if len(apart_pair) >= 2:
                e1, e2 = apart_pair[0], apart_pair[1]
                for day in self.days:
                    d = day.date
                    if (e1, d) in self.worked_day and (e2, d) in self.worked_day:
                        self.model.Add(self.worked_day[(e1, d)] + self.worked_day[(e2, d)] <= 1)

        # 9g. Directives: Together / Meetings (groups that should work on the same day)
        together_groups: List[Tuple[Optional[str], List[str]]] = [
            (None, g) for g in directives.together if len(g) >= 2
        ]
        for m in directives.meetings:
            if len(m.people) >= 2:
                together_groups.append((m.date, m.people))

        for g_idx, (target_date, group) in enumerate(together_groups):
            valid_emps = [e for e in group if e in self.employees_by_id]
            if len(valid_emps) >= 2:
                placed_var = self.model.NewBoolVar(f"together_placed_{g_idx}")
                day_together_vars = []
                for day in self.days:
                    if target_date and day.date != target_date:
                        continue
                    d = day.date
                    day_var = self.model.NewBoolVar(f"together_{g_idx}_{d}")
                    # day_var == 1 implies worked_day == 1 for all valid_emps
                    for e in valid_emps:
                        self.model.Add(self.worked_day[(e, d)] >= day_var)
                    day_together_vars.append(day_var)
                if day_together_vars:
                    self.model.Add(sum(day_together_vars) >= placed_var)
                    self.directive_penalties.append((1 - placed_var) * 25000)

    # -----------------------------------------------------------------------
    # Soft Constraints & Objective Optimization
    # -----------------------------------------------------------------------

    def _apply_soft_constraints_and_objective(self):
        """Constructs weighted penalty terms and adds them to model.Minimize()."""
        penalties: List[cp_model.LinearExpr] = []

        # Include penalties from training flow and manager directives
        penalties.extend(self.directive_penalties)

        # 0. Uncovered time (top priority): cover as many template minutes as possible.
        # Per minute, so one 8-hour slot outweighs two 1-hour ones; a small per-slot
        # part breaks ties toward fewer open slots.
        W_UNCOVERED_MINUTE = 100
        W_UNASSIGNED_SLOT = 1000
        for day in self.days:
            for slot in day.slots:
                penalties.append(self.unassigned[slot.id] * (W_UNASSIGNED_SLOT + slot.minutes * W_UNCOVERED_MINUTE))

        # 0b. Kept shifts from previous schedule during chat edits
        W_KEEP = 2000
        for emp_id, shift_list in self.request.directives.keep.items():
            if emp_id not in self.employees_by_id:
                continue
            for k in shift_list:
                k_date = k.get("date")
                k_start = k.get("start", 0)
                k_end = k.get("end", 1440)
                for day in self.days:
                    if day.date != k_date:
                        continue
                    for slot in day.slots:
                        if slot.start < k_end and k_start < slot.end:
                            # Reward assigning emp_id to this slot
                            penalties.append(-W_KEEP * self.work[(emp_id, day.date, slot.id)])

        # Weights
        W_TARGET_SHIFTS = 120
        W_SHIFT_LENGTH_SHORT = 20  # per minute under 3 hours: a tiny shift of its own only when no one can add the time on
        W_SHIFT_LENGTH_LONG = 2   # per minute over 9 hours (540 mins)
        W_HISTORY_REWARD = 45     # reward (negative penalty) for habitual shift match
        W_DAY_NIGHT = 60          # preference penalty
        W_CLOPEN = 800            # severe clopen penalty

        # 1. Target Shifts Penalty: |total_shifts - target_shifts|
        for emp in (self.roster if self.rules.usual_shifts else []):
            e = emp.id
            # Over: linear. Under: squared, so the people furthest below their usual
            # shifts get them first (two people 1 short beats one person 2 short).
            over = self.model.NewIntVar(0, 7, f"shift_over_{e}")
            self.model.Add(over >= self.total_shifts[e] - emp.target_shifts)
            under = self.model.NewIntVar(0, 7, f"shift_under_{e}")
            self.model.Add(under >= emp.target_shifts - self.total_shifts[e])
            under_sq = self.model.NewIntVar(0, 49, f"shift_under_sq_{e}")
            self.model.AddMultiplicationEquality(under_sq, [under, under])
            penalties.append(over * W_TARGET_SHIFTS)
            penalties.append(under_sq * (W_TARGET_SHIFTS // 2))

        # 2. Shift Length Uniformity Penalty: ideal 3h (180m) to 9h (540m)
        for emp in self.roster:
            e = emp.id
            for day in self.days:
                d = day.date
                # Short shift penalty: if worked_day == 1, penalize max(0, 180 - daily_minutes)
                short_pen = self.model.NewIntVar(0, 180, f"short_{e}_{d}")
                self.model.Add(short_pen >= 180 - self.daily_minutes[(e, d)]).OnlyEnforceIf(self.worked_day[(e, d)])
                self.model.Add(short_pen == 0).OnlyEnforceIf(self.worked_day[(e, d)].Not())
                penalties.append(short_pen * W_SHIFT_LENGTH_SHORT)

                # Long shift penalty: penalize max(0, daily_minutes - 540)
                long_pen = self.model.NewIntVar(0, 900, f"long_{e}_{d}")
                self.model.Add(long_pen >= self.daily_minutes[(e, d)] - 540)
                penalties.append(long_pen * W_SHIFT_LENGTH_LONG)

        # 3. Historical Consistency: reward assigning someone to shifts they usually work
        history_map: Dict[Tuple[str, int], List[HistoryEntryModel]] = {}
        for h in (self.request.history if self.rules.consistency else []):
            history_map.setdefault((h.employee_id, h.weekday), []).append(h)

        for day in self.days:
            d = day.date
            for slot in day.slots:
                s = slot.id
                for emp in self.roster:
                    e = emp.id
                    histories = history_map.get((e, day.weekday), [])
                    for h in histories:
                        # Overlap with historic window
                        if slot.start < h.end and h.start < slot.end:
                            # Apply reward (negative penalty)
                            reward = int(W_HISTORY_REWARD * h.frequency)
                            penalties.append(-reward * self.work[(e, d, s)])

        # 4. Day / Night Preferences
        for day in self.days:
            d = day.date
            for slot in day.slots:
                s = slot.id
                for emp in self.roster:
                    e = emp.id
                    if not self.rules.day_night:
                        continue
                    if emp.day_night_preference == "Daytime":
                        # Penalize evening / closing slots starting >= 14:00 (840) or ending >= 20:00 (1200)
                        if slot.start >= 840 or slot.end >= 1200:
                            penalties.append(self.work[(e, d, s)] * W_DAY_NIGHT)
                    elif emp.day_night_preference == "Night":
                        # Penalize early morning slots starting < 11:00 (660)
                        if slot.start < 660:
                            penalties.append(self.work[(e, d, s)] * W_DAY_NIGHT)

        # 5. Clopen Prevention (Close at >= 21:00 / 1260, Open next morning <= 07:00 / 420)
        close_cutoff = self.rules.clopen_close_end_min
        open_cutoff = self.rules.clopen_open_start_min

        for day1, day2 in (self._next_day_pairs() if self.rules.avoid_clopen else []):
            d1 = day1.date
            d2 = day2.date
            close_slots = [sl for sl in day1.slots if sl.end >= close_cutoff]
            open_slots = [sl for sl in day2.slots if sl.start <= open_cutoff]

            for s_close in close_slots:
                for s_open in open_slots:
                    for emp in self.roster:
                        e = emp.id
                        # Clopen indicator: 1 if both closing and opening
                        clopen_var = self.model.NewBoolVar(f"clopen_{e}_{d1}_{s_close.id}_{s_open.id}")
                        self.model.Add(clopen_var >= self.work[(e, d1, s_close.id)] + self.work[(e, d2, s_open.id)] - 1)
                        penalties.append(clopen_var * W_CLOPEN)

        # Minimize sum of all weighted penalties
        self.model.Minimize(sum(penalties))

    # -----------------------------------------------------------------------
    # Solution Parsing & Response Construction
    # -----------------------------------------------------------------------

    def _build_solution_response(self, status_name: str, solve_time: float) -> SolveScheduleResponse:
        """Parses solver variable assignments into exact Axis ScheduleDay and Shift models."""
        response_days: List[ScheduleDayResponse] = []
        total_slots_covered = 0
        total_labor_minutes = 0
        emp_stats: Dict[str, Dict[str, float]] = {
            e.id: {"shifts": 0, "minutes": 0} for e in self.roster
        }

        for day in self.days:
            d = day.date
            day_shifts: List[ShiftResponse] = []

            # Group assigned slots by employee
            slots_by_emp: Dict[str, List[SlotModel]] = {}
            for slot in day.slots:
                for emp in self.roster:
                    if self.solver.Value(self.work[(emp.id, d, slot.id)]) == 1:
                        slots_by_emp.setdefault(emp.id, []).append(slot)
                        total_slots_covered += 1

            # Construct Shift records
            for emp_id, assigned_slots in slots_by_emp.items():
                if not assigned_slots:
                    continue

                # Sort slots by start time
                assigned_slots.sort(key=lambda s: s.start)
                shift_start = assigned_slots[0].start
                shift_end = assigned_slots[-1].end

                # Pieces on the floor
                pieces: List[ShiftPieceResponse] = []
                for idx, slot in enumerate(assigned_slots):
                    piece_id = f"p_{d}_{emp_id}_{idx}"
                    pieces.append(
                        ShiftPieceResponse(
                            id=piece_id,
                            row_id=slot.row_id,
                            start=slot.start,
                            end=slot.end,
                            admin=False,
                        )
                    )

                # Admin time is added by the client after solving (it has to be joined
                # onto the finished shift, checking availability and daily hours).

                # Check if this shift had a trainee attached
                trainee_id = None
                for sl in assigned_slots:
                    if sl.id in self.trainee_on_slot:
                        trainee_id = self.trainee_on_slot[sl.id]
                        break
                    pair = self.pair_on_slot.get(sl.id)
                    if pair is not None and self.solver.Value(pair[0]) == 1:
                        trainee_id = pair[1]
                        break

                shift_id = f"shift_{d}_{emp_id}"
                shift_obj = ShiftResponse(
                    id=shift_id,
                    user_id=emp_id,
                    trainee_id=trainee_id,
                    start=shift_start,
                    end=shift_end,
                    pieces=pieces,
                    position_segments=[],
                )
                day_shifts.append(shift_obj)

                # Update stats
                emp_minutes = sum(p.minutes for p in pieces)
                emp_stats[emp_id]["shifts"] += 1
                emp_stats[emp_id]["minutes"] += emp_minutes
                total_labor_minutes += emp_minutes * (2 if trainee_id else 1)

            # Sort shifts chronologically by start time
            day_shifts.sort(key=lambda s: s.start)
            day_labor_hours = sum(s.end - s.start for s in day_shifts) / 60.0

            response_days.append(
                ScheduleDayResponse(
                    date=d,
                    template_id=day.template_id,
                    template_name=day.template_name,
                    rows=[
                        ScheduleRowResponse(
                            id=s.row_id,
                            label=s.label,
                            windows=[TimeWindowModel(start=s.start, end=s.end)],
                            allowed_titles=s.allowed_titles,
                        )
                        for s in day.slots
                    ],
                    shifts=day_shifts,
                    labor_hours=round(day_labor_hours, 2),
                )
            )

        # Identify and diagnose open slots
        open_slots: List[OpenSlotResponse] = []
        for day in self.days:
            d = day.date
            for slot in day.slots:
                if self.solver.Value(self.unassigned[slot.id]) == 1:
                    why_reasons: List[str] = []
                    qualified_emps = [
                        e for e in self.roster
                        if not slot.restricted or not set(slot.allowed_titles).isdisjoint({e.title} | set(e.tags))
                    ]
                    if not qualified_emps:
                        why_reasons.append(f"No team members hold required titles/tags: {slot.allowed_titles}")
                    else:
                        avail_count = 0
                        for qe in qualified_emps:
                            scheduled_shifts = emp_stats[qe.id]["shifts"]
                            max_shifts = self.request.directives.max_shifts_override.get(qe.id, qe.max_shifts_per_week)
                            if scheduled_shifts >= max_shifts:
                                continue
                            avail_count += 1
                        if avail_count == 0:
                            why_reasons.append("All qualified team members reached their weekly shift limit")
                        else:
                            why_reasons.append("Qualified team members have availability, time-off, or rest period conflicts")

                    open_slots.append(
                        OpenSlotResponse(
                            id=slot.id,
                            date=d,
                            row_id=slot.row_id,
                            label=slot.label,
                            start=slot.start,
                            end=slot.end,
                            minutes=slot.minutes,
                            why="; ".join(why_reasons) if why_reasons else "Staffing constraints",
                        )
                    )

        # Assemble metrics
        total_slots_needed = sum(len(d.slots) for d in self.days)
        self.logs.append(
            f"Solution found: {total_slots_covered}/{total_slots_needed} slots covered ({len(open_slots)} open)."
        )
        metrics = SolveScheduleMetrics(
            total_slots_needed=total_slots_needed,
            total_slots_covered=total_slots_covered,
            total_labor_hours=round(total_labor_minutes / 60.0, 2),
            employee_stats={
                e.id: EmployeeMetrics(
                    shifts_scheduled=int(emp_stats[e.id]["shifts"]),
                    total_hours=round(emp_stats[e.id]["minutes"] / 60.0, 2),
                    target_shifts=e.target_shifts,
                    target_hours=e.target_hours,
                )
                for e in self.roster
            },
        )

        return SolveScheduleResponse(
            status=status_name,
            solve_time_seconds=solve_time,
            objective_value=float(self.solver.ObjectiveValue()),
            days=response_days,
            open_slots=open_slots,
            metrics=metrics,
            infeasibility_reasons=[],
            logs=self.logs,
        )

    # -----------------------------------------------------------------------
    # Infeasibility Diagnostics
    # -----------------------------------------------------------------------

    def _diagnose_infeasibility(self):
        """Pinpoints the exact slots, roles, or availability conflicts that caused infeasibility."""
        self.logs.append("Analyzing infeasibility root causes...")

        for day in self.days:
            d = day.date
            for slot in day.slots:
                eligible_count = 0
                rejection_reasons = []

                for emp in self.roster:
                    e = emp.id
                    # Role check
                    if slot.restricted and set(slot.allowed_titles).isdisjoint({emp.title} | set(emp.tags)):
                        continue
                    eligible_count += 1

                if eligible_count == 0:
                    reason = f"Slot '{slot.label}' ({slot.id}) on {d} ({slot.start}-{slot.end}) has ZERO qualified employees with required titles/tags: {slot.allowed_titles}."
                    self.infeasibility_reasons.append(reason)
                    self.logs.append(f"CRITICAL: {reason}")

        if not self.infeasibility_reasons:
            self.infeasibility_reasons.append(
                "Infeasible due to combined weekly shift caps, availability overlap, or minimum rest constraints."
            )

    def _all_slots(self) -> List[SlotModel]:
        return [sl for day in self.days for sl in day.slots]

    def _next_day_pairs(self) -> List[Tuple[DayTemplateModel, DayTemplateModel]]:
        """Pairs of days being built that are next to each other on the calendar."""
        by_ordinal = {self.day_ordinal[d.date]: d for d in self.days}
        return [(d, by_ordinal[o + 1]) for o, d in sorted(by_ordinal.items()) if o + 1 in by_ordinal]

    def _slots_for_date(self, date: str) -> List[SlotModel]:
        for day in self.days:
            if day.date == date:
                return day.slots
        return []
