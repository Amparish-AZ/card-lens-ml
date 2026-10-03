from __future__ import annotations

import hashlib
import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .ner_contracts import NerCardAnnotation
from .ner_dataset import validate_ner_dataset


class RegistryError(ValueError):
    """Raised when an immutable dataset cannot be registered or aggregated."""


@dataclass(frozen=True)
class RegistryReport:
    datasets: int
    cards: int
    tokens: int
    splits: dict[str, int]

    def as_json(self) -> str:
        return json.dumps(
            {
                "datasets": self.datasets,
                "cards": self.cards,
                "tokens": self.tokens,
                "splits": self.splits,
            },
            indent=2,
            sort_keys=True,
        )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def register_ner_dataset(
    source: Path,
    registry: Path,
    *,
    dataset_id: str,
    dataset_version: str,
) -> Path:
    report = validate_ner_dataset(source, require_images=True, require_verified=True)
    if not report.valid:
        raise RegistryError("source NER dataset failed validation:\n" + "\n".join(report.errors))
    destination = registry / f"{dataset_id}-v{dataset_version}"
    if destination.exists():
        raise RegistryError(f"immutable dataset already exists: {destination}")

    annotations = source / "annotations" / "cards.jsonl"
    raw_records = [
        json.loads(line) for line in annotations.read_text(encoding="utf-8").splitlines()
    ]
    image_destination = destination / "images"
    image_destination.mkdir(parents=True)
    rewritten: list[dict[str, Any]] = []
    hashes: dict[str, str] = {}
    for raw in raw_records:
        card = NerCardAnnotation.from_mapping(raw)
        source_image = source / card.image
        image_hash = _sha256(source_image)
        if duplicate := hashes.get(image_hash):
            raise RegistryError(f"{card.card_id}: exact image duplicates {duplicate}")
        hashes[image_hash] = card.card_id
        output_name = f"{card.card_id}{source_image.suffix.lower()}"
        shutil.copy2(source_image, image_destination / output_name)
        raw["image"] = f"images/{output_name}"
        rewritten.append(raw)

    annotation_destination = destination / "annotations"
    annotation_destination.mkdir()
    (annotation_destination / "cards.jsonl").write_text(
        "".join(
            f"{json.dumps(record, ensure_ascii=False, sort_keys=True)}\n"
            for record in rewritten
        ),
        encoding="utf-8",
    )
    metadata = {
        "schema_version": 1,
        "dataset_id": dataset_id,
        "dataset_version": dataset_version,
        "cards": report.cards,
        "tokens": report.tokens,
        "source_digest": _sha256(annotations),
    }
    (destination / "dataset.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    registered = validate_ner_dataset(destination, require_images=True, require_verified=True)
    if not registered.valid:
        raise RegistryError(
            "registered dataset failed validation:\n" + "\n".join(registered.errors)
        )
    return destination


def discover_registry(
    registry: Path,
) -> tuple[list[tuple[Path, NerCardAnnotation]], RegistryReport]:
    datasets = sorted(path for path in registry.iterdir() if (path / "dataset.json").is_file())
    cards: list[tuple[Path, NerCardAnnotation]] = []
    seen_ids: set[str] = set()
    seen_hashes: dict[str, str] = {}
    group_splits: dict[str, str] = {}
    split_counts: dict[str, int] = {}
    for dataset in datasets:
        report = validate_ner_dataset(dataset, require_images=True, require_verified=True)
        if not report.valid:
            raise RegistryError(f"{dataset.name} failed validation:\n" + "\n".join(report.errors))
        annotation_file = dataset / "annotations" / "cards.jsonl"
        for line in annotation_file.read_text(encoding="utf-8").splitlines():
            card = NerCardAnnotation.from_mapping(json.loads(line))
            if card.card_id in seen_ids:
                raise RegistryError(f"duplicate card_id across datasets: {card.card_id}")
            seen_ids.add(card.card_id)
            image_hash = _sha256(dataset / card.image)
            if duplicate := seen_hashes.get(image_hash):
                raise RegistryError(f"{card.card_id}: exact image duplicates {duplicate}")
            seen_hashes[image_hash] = card.card_id
            namespaced_group = f"{card.source}:{card.physical_card_group}"
            previous_split = group_splits.setdefault(namespaced_group, card.split)
            if previous_split != card.split:
                raise RegistryError(
                    f"physical card group {namespaced_group!r} leaks across splits"
                )
            split_counts[card.split] = split_counts.get(card.split, 0) + 1
            cards.append((dataset, card))
    return cards, RegistryReport(
        datasets=len(datasets),
        cards=len(cards),
        tokens=sum(len(card.tokens) for _, card in cards),
        splits=dict(sorted(split_counts.items())),
    )
