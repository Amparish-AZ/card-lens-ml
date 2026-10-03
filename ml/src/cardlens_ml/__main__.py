from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path

from .dataset import validate_dataset
from .gates import evaluate_gates
from .ner_dataset import validate_ner_dataset
from .registry import RegistryError, discover_registry, register_ner_dataset
from .release import ReleaseError, install_release, package_release, verify_release
from .source_manifest import parse_same_card_groups, prepare_source_manifest


def _artifact(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("artifact must use NAME=PATH")
    name, raw_path = value.split("=", 1)
    if not name.strip() or not raw_path.strip():
        raise argparse.ArgumentTypeError("artifact must use NAME=PATH")
    return name.strip(), Path(raw_path)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="cardlens_ml")
    commands = root.add_subparsers(dest="command", required=True)

    validate = commands.add_parser("validate-dataset")
    validate.add_argument("--dataset", type=Path, required=True)
    validate.add_argument("--require-images", action="store_true")

    validate_ner = commands.add_parser("validate-ner-dataset")
    validate_ner.add_argument("--dataset", type=Path, required=True)
    validate_ner.add_argument("--require-images", action="store_true")
    validate_ner.add_argument("--require-verified", action="store_true")

    prepare_source = commands.add_parser("prepare-ner-source")
    prepare_source.add_argument("--source-dir", type=Path, required=True)
    prepare_source.add_argument("--output", type=Path, required=True)
    prepare_source.add_argument("--source-name", required=True)
    prepare_source.add_argument("--source-license", default="unknown")
    prepare_source.add_argument("--same-card", action="append", default=[])
    prepare_source.add_argument("--seed", type=int, default=1701)

    register_dataset = commands.add_parser("register-ner-dataset")
    register_dataset.add_argument("--source", type=Path, required=True)
    register_dataset.add_argument("--registry", type=Path, required=True)
    register_dataset.add_argument("--dataset-id", required=True)
    register_dataset.add_argument("--dataset-version", required=True)

    list_registry = commands.add_parser("list-ner-registry")
    list_registry.add_argument("--registry", type=Path, required=True)
    list_registry.add_argument("--output", type=Path)

    package = commands.add_parser("package-release")
    package.add_argument("--model-version", required=True)
    package.add_argument("--dataset-version", required=True)
    package.add_argument("--artifact", action="append", type=_artifact, required=True)
    package.add_argument("--output", type=Path, required=True)
    package.add_argument("--source-revision")

    verify = commands.add_parser("verify-release")
    verify.add_argument("--release", type=Path, required=True)

    install = commands.add_parser("install-release")
    install.add_argument("--release", type=Path, required=True)
    install.add_argument("--project", type=Path, required=True)

    gates = commands.add_parser("evaluate-gates")
    gates.add_argument("--metrics", type=Path, required=True)
    gates.add_argument("--config", type=Path, required=True)
    return root


def main() -> int:
    arguments = parser().parse_args()
    if arguments.command == "validate-dataset":
        report = validate_dataset(arguments.dataset, require_images=arguments.require_images)
        print(report.as_json())
        return 0 if report.valid else 1
    if arguments.command == "validate-ner-dataset":
        ner_report = validate_ner_dataset(
            arguments.dataset,
            require_images=arguments.require_images,
            require_verified=arguments.require_verified,
        )
        print(ner_report.as_json())
        return 0 if ner_report.valid else 1
    if arguments.command == "prepare-ner-source":
        try:
            records = prepare_source_manifest(
                arguments.source_dir,
                arguments.output,
                source_name=arguments.source_name,
                source_license=arguments.source_license,
                same_card_groups=parse_same_card_groups(arguments.same_card),
                seed=arguments.seed,
            )
        except ValueError as error:
            print(f"source preparation failed: {error}")
            return 1
        split_counts: dict[str, int] = {}
        for record in records:
            split = str(record["suggested_split"])
            split_counts[split] = split_counts.get(split, 0) + 1
        print(json.dumps({"images": len(records), "splits": split_counts}, indent=2))
        return 0
    if arguments.command == "register-ner-dataset":
        try:
            registered = register_ner_dataset(
                arguments.source,
                arguments.registry,
                dataset_id=arguments.dataset_id,
                dataset_version=arguments.dataset_version,
            )
        except RegistryError as error:
            print(f"dataset registration failed: {error}")
            return 1
        print(registered)
        return 0
    if arguments.command == "list-ner-registry":
        try:
            _, registry_report = discover_registry(arguments.registry)
        except RegistryError as error:
            print(f"registry validation failed: {error}")
            return 1
        registry_json = registry_report.as_json()
        if arguments.output is not None:
            arguments.output.parent.mkdir(parents=True, exist_ok=True)
            arguments.output.write_text(registry_json + "\n", encoding="utf-8")
        print(registry_json)
        return 0
    if arguments.command == "package-release":
        try:
            release = package_release(
                model_version=arguments.model_version,
                dataset_version=arguments.dataset_version,
                artifacts=dict(arguments.artifact),
                output_root=arguments.output,
                source_revision=arguments.source_revision,
            )
        except ReleaseError as error:
            print(f"release failed: {error}")
            return 1
        print(release)
        return 0
    if arguments.command == "verify-release":
        try:
            verify_release(arguments.release)
        except ReleaseError as error:
            print(f"release verification failed: {error}")
            return 1
        print("release verified")
        return 0
    if arguments.command == "install-release":
        try:
            installed = install_release(arguments.release, arguments.project)
        except ReleaseError as error:
            print(f"release installation failed: {error}")
            return 1
        print("\n".join(str(path) for path in installed))
        return 0
    if arguments.command == "evaluate-gates":
        failures = evaluate_gates(arguments.metrics, arguments.config)
        print(json.dumps([asdict(failure) for failure in failures], indent=2))
        return 1 if failures else 0
    raise AssertionError(f"unsupported command: {arguments.command}")


if __name__ == "__main__":
    raise SystemExit(main())
