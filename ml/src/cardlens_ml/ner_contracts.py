from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal, cast

from .contracts import ALLOWED_SPLITS, Box, ContractError, Split

Entity = Literal["NAME", "TITLE", "COMPANY", "EMAIL", "PHONE", "WEBSITE", "ADDRESS"]

ENTITIES: tuple[Entity, ...] = (
    "NAME",
    "TITLE",
    "COMPANY",
    "EMAIL",
    "PHONE",
    "WEBSITE",
    "ADDRESS",
)
BIO_TAGS = frozenset({"O", *(f"{prefix}-{entity}" for entity in ENTITIES for prefix in "BI")})


@dataclass(frozen=True)
class NerToken:
    ocr_text: str
    truth_text: str
    tag: str
    box: Box
    confidence: float
    line_index: int

    @classmethod
    def from_mapping(cls, value: object) -> NerToken:
        if not isinstance(value, dict):
            raise ContractError("each NER token must be a JSON object")
        data = cast(dict[str, Any], value)
        ocr_text = data.get("ocr_text")
        truth_text = data.get("truth_text")
        tag = data.get("tag")
        confidence = data.get("confidence")
        line_index = data.get("line_index")
        if not isinstance(ocr_text, str):
            raise ContractError("ocr_text must be a string")
        if not isinstance(truth_text, str) or not truth_text.strip():
            raise ContractError("truth_text must be a non-empty string")
        if not isinstance(tag, str) or tag not in BIO_TAGS:
            raise ContractError(f"unsupported BIO tag: {tag!r}")
        if not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
            raise ContractError("confidence must be between 0 and 1")
        if not isinstance(line_index, int) or isinstance(line_index, bool) or line_index < 0:
            raise ContractError("line_index must be a non-negative integer")
        return cls(
            ocr_text=ocr_text,
            truth_text=truth_text.strip(),
            tag=tag,
            box=Box.from_value(data.get("box")),
            confidence=float(confidence),
            line_index=line_index,
        )


@dataclass(frozen=True)
class NerCardAnnotation:
    card_id: str
    physical_card_group: str
    image: str
    source: str
    split: Split
    verified: bool
    tokens: tuple[NerToken, ...]

    @classmethod
    def from_mapping(cls, value: object) -> NerCardAnnotation:
        if not isinstance(value, dict):
            raise ContractError("NER card annotation must be a JSON object")
        data = cast(dict[str, Any], value)
        if data.get("schema_version") != 2:
            raise ContractError("schema_version must be 2 for layout-aware NER")
        card_id = data.get("card_id")
        physical_card_group = data.get("physical_card_group")
        image = data.get("image")
        source = data.get("source")
        split = data.get("split")
        verified = data.get("verified")
        tokens = data.get("tokens")
        for name, raw in (
            ("card_id", card_id),
            ("physical_card_group", physical_card_group),
            ("image", image),
            ("source", source),
        ):
            if not isinstance(raw, str) or not raw.strip():
                raise ContractError(f"{name} must be a non-empty string")
        if not isinstance(split, str) or split not in ALLOWED_SPLITS:
            raise ContractError(f"unsupported split: {split!r}")
        if not isinstance(verified, bool):
            raise ContractError("verified must be a boolean")
        if not isinstance(tokens, list) or not tokens:
            raise ContractError("tokens must contain at least one annotation")
        return cls(
            card_id=cast(str, card_id).strip(),
            physical_card_group=cast(str, physical_card_group).strip(),
            image=cast(str, image).strip(),
            source=cast(str, source).strip(),
            split=cast(Split, split),
            verified=verified,
            tokens=tuple(NerToken.from_mapping(token) for token in tokens),
        )
