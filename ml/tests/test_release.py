import json
from pathlib import Path

import pytest

from cardlens_ml.release import (
    INSTALL_TARGETS,
    ReleaseError,
    install_release,
    package_release,
    verify_release,
)


def test_package_and_verify_release(tmp_path: Path) -> None:
    model = tmp_path / "model.tflite"
    model.write_bytes(b"test-model")
    release = package_release(
        model_version="1.0.0",
        dataset_version="1.0.0",
        artifacts={"field_parser": model},
        output_root=tmp_path / "releases",
        source_revision="abc123",
    )
    verify_release(release)
    manifest = json.loads((release / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"][0]["name"] == "field_parser"


def test_release_detects_modified_artifact(tmp_path: Path) -> None:
    model = tmp_path / "model.onnx"
    model.write_bytes(b"original")
    release = package_release(
        model_version="1.0.0",
        dataset_version="1.0.0",
        artifacts={"ocr": model},
        output_root=tmp_path / "releases",
    )
    (release / "artifacts" / "ocr.onnx").write_bytes(b"modified")
    with pytest.raises(ReleaseError):
        verify_release(release)


def test_install_release_places_all_runtime_models(tmp_path: Path) -> None:
    sources: dict[str, Path] = {}
    for name in INSTALL_TARGETS:
        suffix = ".json" if name.endswith(("metrics", "metadata")) else ".bin"
        source = tmp_path / f"source-{name}{suffix}"
        source.write_bytes(name.encode())
        sources[name] = source
    release = package_release(
        model_version="2.0.0",
        dataset_version="3.0.0",
        artifacts=sources,
        output_root=tmp_path / "releases",
    )
    project = tmp_path / "app"
    installed = install_release(release, project)
    assert len(installed) == len(INSTALL_TARGETS) + 1
    assert (project / "assets/models/model_manifest.json").is_file()
