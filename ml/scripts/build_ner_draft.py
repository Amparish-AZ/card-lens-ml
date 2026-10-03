from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, cast

LABELS = {"O", "NAME", "TITLE", "COMPANY", "EMAIL", "PHONE", "WEBSITE", "ADDRESS"}

EMAIL = re.compile(r"(?:e-?mail:?)?.+@.+\.[a-z]{2,}", re.IGNORECASE)
WEBSITE = re.compile(r"(?:www\.|https?://).+\.[a-z]{2,}", re.IGNORECASE)
PHONE = re.compile(
    r"(?:mob|mobile|cell|tel|fax|ph|off|resi?|\(o\)|\(r\))?[.:]?"
    r"\+?\d[\d():,./+-]{5,}",
    re.IGNORECASE,
)
ADDRESS = re.compile(
    r"(?:road|street|market|nagar|complex|floor|shop|plot|flat|lane|path|"
    r"mumbai|nashik|pune|hyderabad|ahmedabad|salem|indore|kakinada|karnataka|india|"
    r"\b\d{6}\b)",
    re.IGNORECASE,
)
TITLE = re.compile(
    r"(?:manager|director|founder|officer|secretary|executive|ceo|broker|agent|"
    r"consultant|merchant|wholesaler|canvass|proprietor)",
    re.IGNORECASE,
)
COMPANY = re.compile(
    r"(?:company|corporation|traders?|enterprises?|solutions?|agency|agencies|"
    r"marketing|salescorporation|technologies|pvt\.?|ltd\.?|creation|school|project|"
    r"springboard|coworks|tours|infotech|industries|brokers)",
    re.IGNORECASE,
)


def _label(text: str) -> str:
    if EMAIL.fullmatch(text):
        return "EMAIL"
    if WEBSITE.search(text):
        return "WEBSITE"
    if PHONE.search(text):
        return "PHONE"
    if ADDRESS.search(text):
        return "ADDRESS"
    if TITLE.search(text):
        return "TITLE"
    if COMPANY.search(text):
        return "COMPANY"
    return "O"


def _box(points: list[list[float]], width: int, height: int) -> list[float]:
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    x = max(0.0, min(xs) / width)
    y = max(0.0, min(ys) / height)
    box_width = min(1.0 - x, max(xs) / width - x)
    box_height = min(1.0 - y, max(ys) / height - y)
    return [x, y, max(box_width, 1 / width), max(box_height, 1 / height)]


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a reviewable CardLens NER draft")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--ocr", type=Path, required=True)
    parser.add_argument("--overrides", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verified", action="store_true")
    return parser.parse_args()


def _load_jsonl(path: Path, key: str) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            record = cast(dict[str, Any], json.loads(line))
            records[str(record[key])] = record
    return records


def main() -> int:
    options = arguments()
    manifest = _load_jsonl(options.manifest, "image")
    ocr = _load_jsonl(options.ocr, "image")
    overrides = cast(dict[str, dict[str, list[int]]], json.loads(options.overrides.read_text()))
    missing_ocr = sorted(set(manifest) - set(ocr))
    if missing_ocr:
        raise SystemExit(f"OCR output is missing {len(missing_ocr)} images")

    options.output.parent.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, Any]] = []
    for image_name, source in manifest.items():
        recognized = ocr[image_name]
        image_overrides = overrides.get(image_name, {})
        index_labels: dict[int, str] = {}
        for label, indices in image_overrides.items():
            normalized = label.upper()
            if normalized not in LABELS:
                raise SystemExit(f"unsupported override label {label!r} for {image_name}")
            for index in indices:
                if index in index_labels:
                    raise SystemExit(f"duplicate override for {image_name} line {index}")
                index_labels[index] = normalized

        previous_label = "O"
        tokens: list[dict[str, Any]] = []
        for index, line in enumerate(recognized.get("lines", [])):
            text = str(line["text"]).strip()
            label = index_labels.get(index, _label(text))
            continues_entity = label in {"ADDRESS", "COMPANY", "TITLE"} and label == previous_label
            tag = "O" if label == "O" else f"{'I' if continues_entity else 'B'}-{label}"
            tokens.append(
                {
                    "ocr_text": text,
                    "truth_text": text,
                    "tag": tag,
                    "box": _box(
                        line["points"],
                        int(recognized["width"]),
                        int(recognized["height"]),
                    ),
                    "confidence": float(line["confidence"]),
                    "line_index": index,
                }
            )
            previous_label = label
        records.append(
            {
                "schema_version": 2,
                "card_id": source["card_id"],
                "physical_card_group": source["physical_card_group"],
                "image": f"Camera/{image_name}",
                "source": source["source"],
                "split": source["suggested_split"],
                "verified": bool(options.verified),
                "tokens": tokens,
            }
        )

    options.output.write_text(
        "".join(f"{json.dumps(record, ensure_ascii=False)}\n" for record in records),
        encoding="utf-8",
    )
    print(f"Wrote {len(records)} cards to {options.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
