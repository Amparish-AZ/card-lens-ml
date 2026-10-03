import json
from pathlib import Path

from cardlens_ml.gates import evaluate_gates


def test_quality_gates_report_regressions(tmp_path: Path) -> None:
    metrics = tmp_path / "metrics.json"
    config = tmp_path / "pipeline.json"
    metrics.write_text(json.dumps({"ocr": {"character_error_rate": 0.2}}), encoding="utf-8")
    config.write_text(
        json.dumps(
            {
                "quality_gates": {
                    "ocr.character_error_rate": {"operator": "max", "value": 0.12}
                }
            }
        ),
        encoding="utf-8",
    )
    failures = evaluate_gates(metrics, config)
    assert len(failures) == 1
    assert failures[0].metric == "ocr.character_error_rate"

