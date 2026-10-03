import json
from pathlib import Path

import pytest

from cardlens_ml.source_manifest import parse_same_card_groups, prepare_source_manifest


def test_prepare_source_keeps_repeated_views_in_one_split(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    fixtures = (("front.jpg", b"front"), ("angle.jpg", b"angle"), ("other.jpg", b"other"))
    for name, content in fixtures:
        (source / name).write_bytes(content)
    output = tmp_path / "manifest.jsonl"
    records = prepare_source_manifest(
        source,
        output,
        source_name="sample",
        source_license="test-only",
        same_card_groups=parse_same_card_groups(["front.jpg,angle.jpg"]),
    )
    loaded = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]
    assert loaded == records
    views = [record for record in records if record["image"] in {"front.jpg", "angle.jpg"}]
    assert len({record["physical_card_group"] for record in views}) == 1
    assert len({record["suggested_split"] for record in views}) == 1


def test_prepare_source_rejects_exact_duplicate_images(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "a.jpg").write_bytes(b"same")
    (source / "b.jpg").write_bytes(b"same")
    with pytest.raises(ValueError, match="exact duplicate"):
        prepare_source_manifest(
            source,
            tmp_path / "manifest.jsonl",
            source_name="sample",
            source_license="test-only",
        )
