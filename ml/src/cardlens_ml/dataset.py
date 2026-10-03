from __future__ import annotations

import hashlib
import json
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from .contracts import CardAnnotation, ContractError


@dataclass(frozen=True)
class DatasetReport:
    cards: int
    lines: int
    labels: dict[str, int]
    splits: dict[str, int]
    errors: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def valid(self) -> bool:
        return not self.errors

    def as_json(self) -> str:
        value = asdict(self)
        value["valid"] = self.valid
        return json.dumps(value, indent=2, sort_keys=True)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_dataset(dataset_root: Path, *, require_images: bool = False) -> DatasetReport:
    annotations = dataset_root / "annotations" / "cards.jsonl"
    if not annotations.is_file():
        return DatasetReport(0, 0, {}, {}, (f"missing annotation file: {annotations}",), ())

    cards: list[CardAnnotation] = []
    errors: list[str] = []
    warnings: list[str] = []
    seen_ids: set[str] = set()
    image_hashes: dict[str, str] = {}

    for line_number, raw_line in enumerate(annotations.read_text(encoding="utf-8").splitlines(), 1):
        if not raw_line.strip():
            continue
        try:
            raw: Any = json.loads(raw_line)
            card = CardAnnotation.from_mapping(raw)
        except (json.JSONDecodeError, ContractError) as error:
            errors.append(f"line {line_number}: {error}")
            continue
        if card.card_id in seen_ids:
            errors.append(f"line {line_number}: duplicate card_id {card.card_id!r}")
            continue
        seen_ids.add(card.card_id)
        image_path = dataset_root / card.image
        if not image_path.is_file():
            message = f"{card.card_id}: image not found: {card.image}"
            (errors if require_images else warnings).append(message)
        else:
            image_hash = _sha256(image_path)
            duplicate = image_hashes.get(image_hash)
            if duplicate is not None:
                errors.append(f"{card.card_id}: image duplicates {duplicate}")
            else:
                image_hashes[image_hash] = card.card_id
        cards.append(card)

    label_counts = Counter(line.label for card in cards for line in card.lines)
    split_counts = Counter(card.split for card in cards)
    for expected in ("train", "validation", "test"):
        if split_counts[expected] == 0:
            warnings.append(f"dataset has no {expected} cards")

    return DatasetReport(
        cards=len(cards),
        lines=sum(len(card.lines) for card in cards),
        labels=dict(sorted(label_counts.items())),
        splits=dict(sorted(split_counts.items())),
        errors=tuple(errors),
        warnings=tuple(warnings),
    )

