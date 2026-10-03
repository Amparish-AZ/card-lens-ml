from __future__ import annotations

import hashlib
import json
import random
import re
from pathlib import Path

SUPPORTED_IMAGES = frozenset({".jpg", ".jpeg", ".png", ".webp"})


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _identifier(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def parse_same_card_groups(values: list[str]) -> dict[str, str]:
    membership: dict[str, str] = {}
    for group_number, value in enumerate(values, 1):
        members = [member.strip() for member in value.split(",") if member.strip()]
        if len(members) < 2:
            raise ValueError("--same-card requires at least two comma-separated filenames")
        group_id = f"repeated-physical-card-{group_number:03d}"
        for member in members:
            if member in membership:
                raise ValueError(f"image appears in more than one physical-card group: {member}")
            membership[member] = group_id
    return membership


def prepare_source_manifest(
    source_dir: Path,
    output: Path,
    *,
    source_name: str,
    source_license: str,
    same_card_groups: dict[str, str] | None = None,
    seed: int = 1701,
) -> list[dict[str, object]]:
    source_dir = source_dir.resolve()
    images = sorted(
        path
        for path in source_dir.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_IMAGES
    )
    if not images:
        raise ValueError(f"no supported images found under {source_dir}")

    group_membership = same_card_groups or {}
    missing = sorted(set(group_membership) - {path.name for path in images})
    if missing:
        raise ValueError(f"same-card filenames not found: {', '.join(missing)}")

    hashes: dict[str, str] = {}
    prepared: list[tuple[Path, str, str]] = []
    for path in images:
        digest = _sha256(path)
        if duplicate := hashes.get(digest):
            raise ValueError(f"exact duplicate image: {path.name} duplicates {duplicate}")
        hashes[digest] = path.name
        physical_group = group_membership.get(path.name, f"physical-{_identifier(path.stem)}")
        prepared.append((path, digest, physical_group))

    groups = sorted({physical_group for _, _, physical_group in prepared})
    random.Random(seed).shuffle(groups)
    validation_count = max(1, round(len(groups) * 0.15))
    test_count = max(1, round(len(groups) * 0.15))
    validation_groups = set(groups[:validation_count])
    test_groups = set(groups[validation_count : validation_count + test_count])

    records: list[dict[str, object]] = []
    for path, digest, physical_group in prepared:
        split = (
            "validation"
            if physical_group in validation_groups
            else "test"
            if physical_group in test_groups
            else "train"
        )
        records.append(
            {
                "schema_version": 1,
                "card_id": f"{_identifier(source_name)}-{_identifier(path.stem)}",
                "physical_card_group": physical_group,
                "image": path.relative_to(source_dir).as_posix(),
                "sha256": digest,
                "source": source_name,
                "source_license": source_license,
                "suggested_split": split,
                "status": "needs_ocr_and_human_labels",
            }
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "".join(f"{json.dumps(record, sort_keys=True)}\n" for record in records),
        encoding="utf-8",
    )
    return records
