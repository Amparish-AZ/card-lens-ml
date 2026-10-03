import json
from pathlib import Path

from cardlens_ml.ner_dataset import validate_ner_dataset


def test_example_ner_dataset_is_structurally_valid() -> None:
    dataset = Path(__file__).parents[1] / "data" / "ner-example"
    report = validate_ner_dataset(dataset)
    assert report.valid
    assert report.cards == 1
    assert report.tokens == 5
    assert report.tags["B-NAME"] == 1


def test_ner_dataset_rejects_physical_card_split_leakage(tmp_path: Path) -> None:
    annotation_dir = tmp_path / "annotations"
    annotation_dir.mkdir()
    base = {
        "schema_version": 2,
        "physical_card_group": "same-card",
        "image": "missing.jpg",
        "source": "test",
        "verified": True,
        "tokens": [
            {
                "ocr_text": "Avery",
                "truth_text": "Avery",
                "tag": "B-NAME",
                "box": [0.1, 0.1, 0.2, 0.1],
                "confidence": 0.9,
                "line_index": 0,
            }
        ],
    }
    first = {**base, "card_id": "view-a", "split": "train"}
    second = {**base, "card_id": "view-b", "split": "test"}
    (annotation_dir / "cards.jsonl").write_text(
        f"{json.dumps(first)}\n{json.dumps(second)}\n", encoding="utf-8"
    )
    report = validate_ner_dataset(tmp_path)
    assert not report.valid
    assert any("leaks" in error for error in report.errors)
