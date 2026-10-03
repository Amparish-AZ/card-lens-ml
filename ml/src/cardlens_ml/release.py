from __future__ import annotations

import hashlib
import json
import os
import shutil
from datetime import UTC, datetime
from pathlib import Path


class ReleaseError(ValueError):
    """Raised when a model release is incomplete or corrupt."""


INSTALL_TARGETS = {
    "ocr_detector": "android/ppocr-sdk/src/main/assets/models/det/inference.onnx",
    "ocr_recognizer": "android/ppocr-sdk/src/main/assets/models/rec/inference.onnx",
    "ocr_recognizer_config": "android/ppocr-sdk/src/main/assets/models/rec/inference.yml",
    "field_parser": "assets/models/card_field_classifier.tflite",
    "parser_metrics": "assets/models/training_metrics.json",
    "layout_ner": "assets/models/layout_ner.tflite",
    "layout_ner_metadata": "assets/models/layout_ner_metadata.json",
    "layout_ner_metrics": "assets/models/layout_ner_metrics.json",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_release(
    *,
    model_version: str,
    dataset_version: str,
    artifacts: dict[str, Path],
    output_root: Path,
    source_revision: str | None = None,
) -> Path:
    if not model_version.strip() or not dataset_version.strip():
        raise ReleaseError("model and dataset versions must be non-empty")
    missing = [f"{name}: {path}" for name, path in artifacts.items() if not path.is_file()]
    if missing:
        raise ReleaseError("missing model artifacts: " + ", ".join(missing))

    release_dir = output_root / f"cardlens-models-{model_version}"
    if release_dir.exists():
        raise ReleaseError(f"release already exists: {release_dir}")
    artifact_dir = release_dir / "artifacts"
    artifact_dir.mkdir(parents=True)

    manifest_artifacts: list[dict[str, object]] = []
    for name, source in sorted(artifacts.items()):
        destination = artifact_dir / f"{name}{source.suffix}"
        shutil.copy2(source, destination)
        manifest_artifacts.append(
            {
                "name": name,
                "file": destination.relative_to(release_dir).as_posix(),
                "sha256": sha256(destination),
                "bytes": destination.stat().st_size,
            }
        )

    manifest = {
        "schema_version": 1,
        "model_version": model_version,
        "dataset_version": dataset_version,
        "created_at": datetime.now(UTC).isoformat(),
        "source_revision": source_revision or os.environ.get("GITHUB_SHA"),
        "artifacts": manifest_artifacts,
    }
    (release_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    verify_release(release_dir)
    return release_dir


def verify_release(release_dir: Path) -> None:
    manifest_path = release_dir / "manifest.json"
    if not manifest_path.is_file():
        raise ReleaseError(f"missing release manifest: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ReleaseError(f"invalid release manifest: {error}") from error
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ReleaseError("release manifest contains no artifacts")
    for raw in artifacts:
        if not isinstance(raw, dict):
            raise ReleaseError("invalid artifact entry")
        relative_file = raw.get("file")
        expected_hash = raw.get("sha256")
        expected_bytes = raw.get("bytes")
        if not isinstance(relative_file, str) or not isinstance(expected_hash, str):
            raise ReleaseError("artifact file and sha256 are required")
        artifact = release_dir / relative_file
        if not artifact.is_file():
            raise ReleaseError(f"missing release artifact: {relative_file}")
        if artifact.stat().st_size != expected_bytes:
            raise ReleaseError(f"size mismatch: {relative_file}")
        if sha256(artifact) != expected_hash:
            raise ReleaseError(f"checksum mismatch: {relative_file}")


def install_release(release_dir: Path, project_root: Path) -> tuple[Path, ...]:
    """Install a verified release into the Flutter project model locations."""
    verify_release(release_dir)
    manifest = json.loads((release_dir / "manifest.json").read_text(encoding="utf-8"))
    raw_artifacts = manifest["artifacts"]
    by_name = {item["name"]: item for item in raw_artifacts}
    missing = sorted(set(INSTALL_TARGETS) - set(by_name))
    if missing:
        raise ReleaseError("release cannot be installed; missing: " + ", ".join(missing))

    installed: list[Path] = []
    for name, relative_target in INSTALL_TARGETS.items():
        source = release_dir / by_name[name]["file"]
        target = project_root / relative_target
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        installed.append(target)
    manifest_target = project_root / "assets" / "models" / "model_manifest.json"
    shutil.copy2(release_dir / "manifest.json", manifest_target)
    installed.append(manifest_target)
    return tuple(installed)
