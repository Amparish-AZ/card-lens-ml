from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast


@dataclass(frozen=True)
class GateFailure:
    metric: str
    actual: float | None
    operator: str
    required: float


def _metric(metrics: dict[str, Any], dotted_name: str) -> float | None:
    current: Any = metrics
    for part in dotted_name.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return float(current) if isinstance(current, (int, float)) else None


def evaluate_gates(metrics_path: Path, config_path: Path) -> tuple[GateFailure, ...]:
    metrics = cast(dict[str, Any], json.loads(metrics_path.read_text(encoding="utf-8")))
    config = cast(dict[str, Any], json.loads(config_path.read_text(encoding="utf-8")))
    raw_gates = config.get("quality_gates", {})
    if not isinstance(raw_gates, dict):
        raise ValueError("quality_gates must be an object")
    failures: list[GateFailure] = []
    for name, raw_rule in raw_gates.items():
        if not isinstance(name, str) or not isinstance(raw_rule, dict):
            raise ValueError("invalid quality gate")
        operator = raw_rule.get("operator")
        required = raw_rule.get("value")
        if operator not in {"min", "max"} or not isinstance(required, (int, float)):
            raise ValueError(f"invalid quality gate for {name}")
        actual = _metric(metrics, name)
        failed = actual is None or (operator == "min" and actual < required) or (
            operator == "max" and actual > required
        )
        if failed:
            failures.append(GateFailure(name, actual, operator, float(required)))
    return tuple(failures)

