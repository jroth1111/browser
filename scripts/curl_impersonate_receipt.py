#!/usr/bin/env python3
"""Create and verify a deterministic curl-impersonate build receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any


RECEIPT_NAME = "chimera-curl-impersonate.json"


def _load_object(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON object {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _is_direct_executable(path: Path) -> bool:
    try:
        mode = path.lstat().st_mode
    except OSError:
        return False
    return stat.S_ISREG(mode) and os.access(path, os.X_OK)


def _safe_artifact_path(raw: str) -> PurePosixPath:
    path = PurePosixPath(raw)
    if not raw or path.is_absolute() or ".." in path.parts or "." in path.parts:
        raise ValueError(f"unsafe receipt artifact path: {raw!r}")
    return path


def _normalize_url(value: str) -> str:
    normalized = value.strip().rstrip("/")
    return normalized[:-4] if normalized.endswith(".git") else normalized


def _git_output(source: Path, *args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(source), *args],
            text=True,
            stderr=subprocess.STDOUT,
            timeout=10,
        ).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise ValueError(f"cannot inspect curl-impersonate source {source}: {exc}") from exc


def _artifact_hashes(package_root: Path, receipt_path: Path) -> dict[str, str]:
    artifacts: dict[str, str] = {}
    for path in sorted(package_root.rglob("*")):
        if not path.is_file() or path == receipt_path:
            continue
        relative = path.relative_to(package_root).as_posix()
        artifacts[relative] = _sha256(path)
    return artifacts


def validate_source_contract(*, lock_path: Path, source: Path, target: str) -> dict[str, Any]:
    lock = _load_object(lock_path)
    expected_commit = str(lock.get("source_commit", ""))
    expected_url = str(lock.get("source_url", ""))
    expected_target = str(lock.get("target", ""))
    source_commit = _git_output(source, "rev-parse", "HEAD")
    source_url = _git_output(source, "remote", "get-url", "origin")
    if source_commit != expected_commit:
        raise ValueError(f"source commit mismatch: expected {expected_commit}, got {source_commit}")
    if _normalize_url(source_url) != _normalize_url(expected_url):
        raise ValueError(f"source URL mismatch: expected {expected_url}, got {source_url}")
    if target != expected_target:
        raise ValueError(f"target mismatch: expected {expected_target}, got {target}")
    return lock


def write_receipt(*, lock_path: Path, source: Path, package_root: Path, target: str) -> Path:
    lock = validate_source_contract(lock_path=lock_path, source=source, target=target)
    expected_url = str(lock.get("source_url", ""))
    source_commit = str(lock.get("source_commit", ""))

    receipt_path = package_root / "share" / RECEIPT_NAME
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": lock.get("receipt_schema"),
        "source_name": lock.get("source_name"),
        "source_url": expected_url,
        "source_tag": lock.get("source_tag"),
        "source_commit": source_commit,
        "target": target,
        "runtime_executable": lock.get("runtime_executable"),
        "artifacts": _artifact_hashes(package_root, receipt_path),
    }
    serialized = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{RECEIPT_NAME}.", dir=receipt_path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(serialized)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, receipt_path)
        directory_fd = os.open(receipt_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    return receipt_path


def validate_receipt(*, lock_path: Path, receipt_path: Path, check_artifacts: bool = True) -> list[str]:
    errors: list[str] = []
    try:
        lock = _load_object(lock_path)
        receipt = _load_object(receipt_path)
    except ValueError as exc:
        return [str(exc)]
    for field in (
        "source_name",
        "source_url",
        "source_tag",
        "source_commit",
        "target",
        "runtime_executable",
    ):
        if receipt.get(field) != lock.get(field):
            errors.append(f"{field} mismatch: expected {lock.get(field)!r}, got {receipt.get(field)!r}")
    if receipt.get("schema") != lock.get("receipt_schema"):
        errors.append(
            f"schema mismatch: expected {lock.get('receipt_schema')!r}, got {receipt.get('schema')!r}"
        )
    artifacts = receipt.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        errors.append("receipt artifacts must be a non-empty object")
        return errors
    package_root = receipt_path.parent.parent
    checked: set[str] = set()
    for raw_path, expected_hash in artifacts.items():
        if not isinstance(raw_path, str) or not isinstance(expected_hash, str):
            errors.append("receipt artifact keys and hashes must be strings")
            continue
        try:
            relative = _safe_artifact_path(raw_path)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        checked.add(raw_path)
        artifact = package_root.joinpath(*relative.parts)
        if not artifact.is_file():
            errors.append(f"missing receipt artifact: {raw_path}")
        elif check_artifacts and _sha256(artifact) != expected_hash:
            errors.append(f"artifact hash mismatch: {raw_path}")
    required = lock.get("required_artifacts")
    if not isinstance(required, list) or not all(isinstance(item, str) for item in required):
        errors.append("source lock required_artifacts must be a string array")
    else:
        for required_path in required:
            if required_path not in checked:
                errors.append(f"required artifact absent from receipt: {required_path}")
    runtime_raw = lock.get("runtime_executable")
    if not isinstance(runtime_raw, str):
        errors.append("source lock runtime_executable must be a string")
    else:
        try:
            runtime_relative = _safe_artifact_path(runtime_raw)
        except ValueError as exc:
            errors.append(str(exc))
        else:
            runtime = package_root.joinpath(*runtime_relative.parts)
            if runtime_raw not in checked:
                errors.append("runtime executable absent from receipt artifacts")
            elif not _is_direct_executable(runtime):
                errors.append(f"runtime executable is not a regular executable file: {runtime_raw}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    write = subparsers.add_parser("write")
    write.add_argument("--lock", required=True, type=Path)
    write.add_argument("--source", required=True, type=Path)
    write.add_argument("--package", required=True, type=Path)
    write.add_argument("--target", required=True)
    source = subparsers.add_parser("source")
    source.add_argument("--lock", required=True, type=Path)
    source.add_argument("--source", required=True, type=Path)
    source.add_argument("--target", required=True)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--lock", required=True, type=Path)
    verify.add_argument("--receipt", required=True, type=Path)
    verify.add_argument("--metadata-only", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "source":
            validate_source_contract(
                lock_path=args.lock.resolve(),
                source=args.source.resolve(),
                target=args.target,
            )
            receipt = args.source.resolve()
            errors = []
            success_label = "curl-impersonate source contract valid"
        elif args.command == "write":
            receipt = write_receipt(
                lock_path=args.lock.resolve(),
                source=args.source.resolve(),
                package_root=args.package.resolve(),
                target=args.target,
            )
            errors = validate_receipt(lock_path=args.lock.resolve(), receipt_path=receipt)
            success_label = "curl-impersonate receipt valid"
        else:
            receipt = args.receipt.resolve()
            errors = validate_receipt(
                lock_path=args.lock.resolve(),
                receipt_path=receipt,
                check_artifacts=not args.metadata_only,
            )
            success_label = "curl-impersonate receipt valid"
    except ValueError as exc:
        errors = [str(exc)]
    if errors:
        for error in errors:
            print(f"error: {error}")
        return 1
    print(f"{success_label}: {receipt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
