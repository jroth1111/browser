from __future__ import annotations

import importlib.util
import json
import subprocess
from pathlib import Path

import pytest


SCRIPT = Path(__file__).resolve().parents[1] / "curl_impersonate_receipt.py"
SPEC = importlib.util.spec_from_file_location("curl_impersonate_receipt", SCRIPT)
assert SPEC and SPEC.loader
receipt_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(receipt_module)


def _source(tmp_path: Path) -> tuple[Path, str]:
    source = tmp_path / "source"
    source.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "config", "user.name", "Receipt Test"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "config", "user.email", "receipt@example.invalid"], cwd=source, check=True, timeout=10)
    subprocess.run(
        ["git", "remote", "add", "origin", "https://example.invalid/curl-impersonate.git"],
        cwd=source,
        check=True,
        timeout=10,
    )
    (source / "README").write_text("fixture\n", encoding="utf-8")
    subprocess.run(["git", "add", "README"], cwd=source, check=True, timeout=10)
    subprocess.run(["git", "commit", "-qm", "fixture"], cwd=source, check=True, timeout=10)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True, timeout=10).strip()
    return source, commit


def _lock(tmp_path: Path, commit: str) -> Path:
    lock = tmp_path / "lock.json"
    lock.write_text(
        json.dumps(
            {
                "schema": "chimera-curl-impersonate-source/v1",
                "receipt_schema": "chimera-curl-impersonate-receipt/v3",
                "source_name": "fixture",
                "source_url": "https://example.invalid/curl-impersonate.git",
                "source_tag": "fixture-v1",
                "source_commit": commit,
                "target": "chrome136",
                "runtime_executable": "bin/curl_chrome136",
                "required_artifacts": [
                    "bin/curl_chrome136",
                    "lib/libcurl-impersonate.a",
                ],
            }
        ),
        encoding="utf-8",
    )
    return lock


def test_write_and_verify_binds_source_target_and_artifact_bytes(tmp_path: Path) -> None:
    source, commit = _source(tmp_path)
    lock = _lock(tmp_path, commit)
    package = tmp_path / "package"
    (package / "bin").mkdir(parents=True)
    runtime = package / "bin" / "curl_chrome136"
    runtime.write_bytes(b"#!/bin/sh\nexit 0\n")
    runtime.chmod(0o755)
    (package / "lib").mkdir(parents=True)
    (package / "lib" / "libcurl-impersonate.a").write_bytes(b"archive-v1")

    receipt = receipt_module.write_receipt(
        lock_path=lock,
        source=source,
        package_root=package,
        target="chrome136",
    )

    assert receipt_module.validate_receipt(lock_path=lock, receipt_path=receipt) == []
    (package / "lib" / "libcurl-impersonate.a").write_bytes(b"tampered")
    assert receipt_module.validate_receipt(lock_path=lock, receipt_path=receipt) == [
        "artifact hash mismatch: lib/libcurl-impersonate.a"
    ]


@pytest.mark.parametrize("field", ["source_commit", "target", "source_url"])
def test_stale_source_contract_fails_before_receipt_write(tmp_path: Path, field: str) -> None:
    source, commit = _source(tmp_path)
    lock = _lock(tmp_path, commit)
    payload = json.loads(lock.read_text(encoding="utf-8"))
    payload[field] = {"source_commit": "0" * 40, "target": "chrome145", "source_url": "https://invalid"}[field]
    lock.write_text(json.dumps(payload), encoding="utf-8")
    package = tmp_path / "package"
    (package / "bin").mkdir(parents=True)
    runtime = package / "bin" / "curl_chrome136"
    runtime.write_bytes(b"#!/bin/sh\nexit 0\n")
    runtime.chmod(0o755)
    (package / "lib").mkdir(parents=True)
    (package / "lib" / "libcurl-impersonate.a").write_bytes(b"archive")

    with pytest.raises(ValueError, match="mismatch"):
        receipt_module.write_receipt(
            lock_path=lock,
            source=source,
            package_root=package,
            target="chrome136",
        )


def test_receipt_rejects_escaping_artifact_path(tmp_path: Path) -> None:
    source, commit = _source(tmp_path)
    lock = _lock(tmp_path, commit)
    receipt = tmp_path / "package" / "share" / receipt_module.RECEIPT_NAME
    receipt.parent.mkdir(parents=True)
    receipt.write_text(
        json.dumps(
            {
                "schema": "chimera-curl-impersonate-receipt/v3",
                "source_name": "fixture",
                "source_url": "https://example.invalid/curl-impersonate.git",
                "source_tag": "fixture-v1",
                "source_commit": commit,
                "target": "chrome136",
                "runtime_executable": "bin/curl_chrome136",
                "artifacts": {"../escape": "0" * 64},
            }
        ),
        encoding="utf-8",
    )

    assert receipt_module.validate_receipt(lock_path=lock, receipt_path=receipt) == [
        "unsafe receipt artifact path: '../escape'",
        "required artifact absent from receipt: bin/curl_chrome136",
        "required artifact absent from receipt: lib/libcurl-impersonate.a",
        "runtime executable absent from receipt artifacts",
    ]


def test_receipt_binds_one_executable_and_ignores_later_unreceipted_candidates(
    tmp_path: Path,
) -> None:
    source, commit = _source(tmp_path)
    lock = _lock(tmp_path, commit)
    package = tmp_path / "package"
    (package / "bin").mkdir(parents=True)
    runtime = package / "bin" / "curl_chrome136"
    runtime.write_bytes(b"#!/bin/sh\nexit 0\n")
    runtime.chmod(0o755)
    (package / "lib").mkdir(parents=True)
    (package / "lib" / "libcurl-impersonate.a").write_bytes(b"archive-v1")
    receipt = receipt_module.write_receipt(
        lock_path=lock,
        source=source,
        package_root=package,
        target="chrome136",
    )

    planted = package / "bin" / "curl_chrome135"
    planted.write_bytes(b"#!/bin/sh\nexit 99\n")
    planted.chmod(0o755)

    assert receipt_module.validate_receipt(lock_path=lock, receipt_path=receipt) == []
    payload = json.loads(receipt.read_text(encoding="utf-8"))
    assert payload["runtime_executable"] == "bin/curl_chrome136"
    assert "bin/curl_chrome135" not in payload["artifacts"]


def test_receipt_rejects_nonexecutables_and_leaf_symlinks(tmp_path: Path) -> None:
    source, commit = _source(tmp_path)
    lock = _lock(tmp_path, commit)
    package = tmp_path / "package"
    (package / "bin").mkdir(parents=True)
    runtime = package / "bin" / "curl_chrome136"
    runtime.write_bytes(b"#!/bin/sh\nexit 0\n")
    runtime.chmod(0o755)
    (package / "lib").mkdir(parents=True)
    (package / "lib" / "libcurl-impersonate.a").write_bytes(b"archive-v1")
    receipt = receipt_module.write_receipt(
        lock_path=lock,
        source=source,
        package_root=package,
        target="chrome136",
    )

    runtime.chmod(0o644)
    assert receipt_module.validate_receipt(lock_path=lock, receipt_path=receipt) == [
        "runtime executable is not a regular executable file: bin/curl_chrome136"
    ]

    target = tmp_path / "replacement"
    target.write_bytes(runtime.read_bytes())
    target.chmod(0o755)
    runtime.unlink()
    runtime.symlink_to(target)
    assert receipt_module.validate_receipt(lock_path=lock, receipt_path=receipt) == [
        "runtime executable is not a regular executable file: bin/curl_chrome136"
    ]
