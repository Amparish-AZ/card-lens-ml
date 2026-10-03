import json
from pathlib import Path

from cardlens_ml.registry import discover_registry, register_ner_dataset


def _source_dataset(root: Path) -> Path:
    source = root / "source"
    (source / "annotations").mkdir(parents=True)
    (source / "images").mkdir()
    (source / "images" / "card.jpg").write_bytes(b"image")
    card = {
        "schema_version": 2,
        "card_id": "card-1",
        "physical_card_group": "physical-1",
        "image": "images/card.jpg",
        "source": "test",
        "split": "train",
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
    (source / "annotations" / "cards.jsonl").write_text(
        json.dumps(card) + "\n", encoding="utf-8"
    )
    return source


def test_register_and_discover_verified_dataset(tmp_path: Path) -> None:
    source = _source_dataset(tmp_path)
    registry = tmp_path / "registry"
    registered = register_ner_dataset(
        source, registry, dataset_id="sample", dataset_version="1.0.0"
    )
    assert (registered / "dataset.json").is_file()
    cards, report = discover_registry(registry)
    assert report.datasets == 1
    assert report.cards == 1
    assert report.tokens == 1
    assert cards[0][1].card_id == "card-1"
