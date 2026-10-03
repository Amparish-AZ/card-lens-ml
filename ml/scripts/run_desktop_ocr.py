from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path

from cardlens_ml.desktop_ocr import DesktopPaddleOcr


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run CardLens PP-OCRv6 on desktop images")
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--detector", type=Path, required=True)
    parser.add_argument("--recognizer", type=Path, required=True)
    parser.add_argument("--recognizer-yaml", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=1600)
    return parser.parse_args()


def main() -> int:
    options = arguments()
    engine = DesktopPaddleOcr(options.detector, options.recognizer, options.recognizer_yaml)
    images = sorted(
        path
        for path in options.images.rglob("*")
        if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    )
    if not images:
        raise SystemExit(f"no images found under {options.images}")
    options.output.parent.mkdir(parents=True, exist_ok=True)
    with options.output.open("w", encoding="utf-8") as destination:
        for index, image in enumerate(images, 1):
            try:
                result = engine.recognize(image, limit_side=options.limit)
                record = {
                    "image": image.relative_to(options.images).as_posix(),
                    **asdict(result),
                }
            except Exception as error:  # noqa: BLE001 - preserve per-image batch progress
                record = {
                    "image": image.relative_to(options.images).as_posix(),
                    "error": str(error),
                }
            destination.write(f"{json.dumps(record, ensure_ascii=False)}\n")
            destination.flush()
            print(
                f"[{index}/{len(images)}] {image.name}: "
                f"{len(record.get('lines', []))} lines, {record.get('elapsed_ms', 0)} ms"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
