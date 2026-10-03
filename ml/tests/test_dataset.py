from pathlib import Path

from cardlens_ml.dataset import validate_dataset


def test_example_dataset_is_structurally_valid() -> None:
    dataset = Path(__file__).parents[1] / "data" / "example"
    report = validate_dataset(dataset)
    assert report.valid
    assert report.cards == 1
    assert report.lines == 4
    assert report.labels["name"] == 1
    assert any("image not found" in warning for warning in report.warnings)

