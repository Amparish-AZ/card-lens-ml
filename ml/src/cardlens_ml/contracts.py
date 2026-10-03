from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal, cast

Label = Literal["name", "title", "company", "email", "phone", "website", "address", "other"]
Split = Literal["train", "validation", "test"]

ALLOWED_LABELS = frozenset(
    {"name", "title", "company", "email", "phone", "website", "address", "other"}
)
ALLOWED_SPLITS = frozenset({"train", "validation", "test"})


class ContractError(ValueError):
    """Raised when a dataset record violates the CardLens contract."""


@dataclass(frozen=True)
class Box:
    x: float
    y: float
    width: float
    height: float

    @classmethod
    def from_value(cls, value: object) -> Box:
        if not isinstance(value, list) or len(value) != 4:
            raise ContractError("box must contain normalized [x, y, width, height]")
        if not all(isinstance(item, (int, float)) for item in value):
            raise ContractError("box values must be numbers")
        x, y, width, height = (float(item) for item in value)
        if not (0 <= x <= 1 and 0 <= y <= 1 and 0 < width <= 1 and 0 < height <= 1):
            raise ContractError("box values must be normalized to the range 0..1")
        if x + width > 1.001 or y + height > 1.001:
            raise ContractError("box must remain inside the normalized image boundary")
        return cls(x=x, y=y, width=width, height=height)


@dataclass(frozen=True)
class LineAnnotation:
    ocr_text: str
    truth_text: str
    label: Label
    box: Box

    @classmethod
    def from_mapping(cls, value: object) -> LineAnnotation:
        if not isinstance(value, dict):
            raise ContractError("each line must be a JSON object")
        data = cast(dict[str, Any], value)
        ocr_text = data.get("ocr_text")
        truth_text = data.get("truth_text")
        label = data.get("label")
        if not isinstance(ocr_text, str):
            raise ContractError("ocr_text must be a string")
        if not isinstance(truth_text, str) or not truth_text.strip():
            raise ContractError("truth_text must be a non-empty string")
        if not isinstance(label, str) or label not in ALLOWED_LABELS:
            raise ContractError(f"unsupported field label: {label!r}")
        return cls(
            ocr_text=ocr_text,
            truth_text=truth_text.strip(),
            label=cast(Label, label),
            box=Box.from_value(data.get("box")),
        )


@dataclass(frozen=True)
class CardAnnotation:
    card_id: str
    image: str
    split: Split
    lines: tuple[LineAnnotation, ...]

    @classmethod
    def from_mapping(cls, value: object) -> CardAnnotation:
        if not isinstance(value, dict):
            raise ContractError("card annotation must be a JSON object")
        data = cast(dict[str, Any], value)
        if data.get("schema_version") != 1:
            raise ContractError("schema_version must be 1")
        card_id = data.get("card_id")
        image = data.get("image")
        split = data.get("split")
        lines = data.get("lines")
        if not isinstance(card_id, str) or not card_id.strip():
            raise ContractError("card_id must be a non-empty string")
        if not isinstance(image, str) or not image.strip():
            raise ContractError("image must be a non-empty relative path")
        if not isinstance(split, str) or split not in ALLOWED_SPLITS:
            raise ContractError(f"unsupported split: {split!r}")
        if not isinstance(lines, list) or not lines:
            raise ContractError("lines must contain at least one annotation")
        return cls(
            card_id=card_id.strip(),
            image=image.strip(),
            split=cast(Split, split),
            lines=tuple(LineAnnotation.from_mapping(item) for item in lines),
        )

