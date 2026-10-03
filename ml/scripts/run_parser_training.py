"""Run the existing CardLens TFLite parser trainer from any working directory."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    project_root = Path(__file__).resolve().parents[2]
    trainer = project_root / "tool" / "train_field_classifier.py"
    if not trainer.is_file():
        print(f"parser trainer not found: {trainer}", file=sys.stderr)
        return 2
    completed = subprocess.run([sys.executable, str(trainer)], cwd=project_root, check=False)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())

