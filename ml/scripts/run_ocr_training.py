"""Fine-tune and export PP-OCRv6 Small using an external PaddleOCR checkout."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def command_line() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--paddle-root", type=Path, required=True)
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--pretrained", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--learning-rate", type=float, default=0.0001)
    return parser.parse_args()


def main() -> int:
    args = command_line()
    config = args.paddle_root / "configs" / "rec" / "PP-OCRv6" / "PP-OCRv6_small_rec.yml"
    trainer = args.paddle_root / "tools" / "train.py"
    exporter = args.paddle_root / "tools" / "export_model.py"
    train_labels = args.dataset / "recognition" / "train.txt"
    validation_labels = args.dataset / "recognition" / "validation.txt"
    required = (config, trainer, exporter, args.pretrained, train_labels, validation_labels)
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        print("OCR training inputs are missing:\n" + "\n".join(missing), file=sys.stderr)
        return 2

    train_output = args.output / "training"
    inference_output = args.output / "inference"
    overrides = [
        f"Global.pretrained_model={args.pretrained}",
        f"Global.save_model_dir={train_output}",
        f"Global.epoch_num={args.epochs}",
        f"Optimizer.lr.learning_rate={args.learning_rate}",
        f"Train.dataset.data_dir={args.dataset / 'recognition'}",
        f"Train.dataset.label_file_list=[{train_labels}]",
        f"Eval.dataset.data_dir={args.dataset / 'recognition'}",
        f"Eval.dataset.label_file_list=[{validation_labels}]",
    ]
    train_command = [sys.executable, str(trainer), "-c", str(config), "-o", *overrides]
    completed = subprocess.run(train_command, cwd=args.paddle_root, check=False)
    if completed.returncode != 0:
        return completed.returncode

    best_model = train_output / "best_accuracy"
    export_command = [
        sys.executable,
        str(exporter),
        "-c",
        str(config),
        "-o",
        f"Global.pretrained_model={best_model}",
        f"Global.save_inference_dir={inference_output}",
    ]
    return subprocess.run(export_command, cwd=args.paddle_root, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())

