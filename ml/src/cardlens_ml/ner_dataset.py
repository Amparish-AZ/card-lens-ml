from __future__ import annotations

import hashlib
import json
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from .contracts import ContractError
from .ner_contracts import NerCardAnnotation


@dataclass(frozen=True)
class NerDatasetReport:
    cards: int
    verified_cards: int
    tokens: int
    tags: dict[str, int]
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


def _bio_errors(card: NerCardAnnotation) -> list[str]:
    errors: list[str] = []
    previous_entity: str | None = None
    for index, token in enumerate(card.tokens):
        if token.tag == "O":
            previous_entity = None
            continue
        prefix, entity = token.tag.split("-", 1)
        if prefix == "I" and previous_entity != entity:
            errors.append(
                f"{card.card_id}: token {index} uses {token.tag} without a preceding "
                f"B-{entity} or I-{entity}"
            )
        previous_entity = entity
    return errors


def validate_ner_dataset(
    dataset_root: Path,
    *,
    require_images: bool = False,
    require_verified: bool = False,
) -> NerDatasetReport:
    annotations = dataset_root / "annotations" / "cards.jsonl"
    if not annotations.is_file():
        return NerDatasetReport(
            0, 0, 0, {}, {}, (f"missing annotation file: {annotations}",), ()
        )

    cards: list[NerCardAnnotation] = []
    errors: list[str] = []
    warnings: list[str] = []
    seen_ids: set[str] = set()
    image_hashes: dict[str, str] = {}
    group_splits: dict[str, str] = {}

    for line_number, raw_line in enumerate(annotations.read_text(encoding="utf-8").splitlines(), 1):
        if not raw_line.strip():
            continue
        try:
            raw: Any = json.loads(raw_line)
            card = NerCardAnnotation.from_mapping(raw)
        except (json.JSONDecodeError, ContractError) as error:
            errors.append(f"line {line_number}: {error}")
            continue
        if card.card_id in seen_ids:
            errors.append(f"line {line_number}: duplicate card_id {card.card_id!r}")
            continue
        seen_ids.add(card.card_id)
        prior_split = group_splits.setdefault(card.physical_card_group, card.split)
        if prior_split != card.split:
            errors.append(
                f"{card.card_id}: physical card group {card.physical_card_group!r} leaks "
                f"across {prior_split} and {card.split}"
            )
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
        if not card.verified:
            message = f"{card.card_id}: annotation has not been human-verified"
            (errors if require_verified else warnings).append(message)
        errors.extend(_bio_errors(card))
        cards.append(card)

    split_counts = Counter(card.split for card in cards)
    for expected in ("train", "validation", "test"):
        if split_counts[expected] == 0:
            warnings.append(f"dataset has no {expected} cards")
    return NerDatasetReport(
        cards=len(cards),
        verified_cards=sum(card.verified for card in cards),
        tokens=sum(len(card.tokens) for card in cards),
        tags=dict(sorted(Counter(token.tag for card in cards for token in card.tokens).items())),
        splits=dict(sorted(split_counts.items())),
        errors=tuple(errors),
        warnings=tuple(warnings),
    )
