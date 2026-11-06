#!/usr/bin/env python3
"""Fast, dependency-free checks for the Phase 0 Go-Ye delivery baseline.

These checks protect required architecture and safety documentation until the
application-level test suites arrive in Phase 1.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = (
    ".env.example",
    ".gitignore",
    "docs/ARCHITECTURE.md",
    "docs/DECISIONS.md",
    "docs/PROGRESS.md",
)

REQUIRED_ARCHITECTURE_TERMS = (
    "COUNTRY > REGION > PROVINCE > ZONE > AREA > PARISH",
    "ltree",
    "row-level security",
    "required consent",
    "Unassigned Pool",
    "mask_phone_numbers_above_parish",
    "Firebase Cloud Messaging",
    "Android `.apk` / `.aab`",
    "iOS archive / `.ipa`",
    "Windows portable `GoYe.exe` / `GoYe-Setup.exe`",
)

REQUIRED_DECISION_IDS = tuple(f"ADR-{number:03d}" for number in range(1, 12))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    for relative_path in REQUIRED_FILES:
        path = ROOT / relative_path
        require(path.is_file(), f"Missing required foundation file: {relative_path}")

    architecture = (ROOT / "docs/ARCHITECTURE.md").read_text(encoding="utf-8")
    decisions = (ROOT / "docs/DECISIONS.md").read_text(encoding="utf-8")
    progress = (ROOT / "docs/PROGRESS.md").read_text(encoding="utf-8")
    env_example = (ROOT / ".env.example").read_text(encoding="utf-8")
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

    for term in REQUIRED_ARCHITECTURE_TERMS:
        require(term in architecture, f"Architecture is missing required term: {term}")
    for decision_id in REQUIRED_DECISION_IDS:
        require(decision_id in decisions, f"Decision register is missing {decision_id}")

    require("awaiting sponsor approval" in progress.lower(), "Progress must retain the approval gate")
    require("PII_ENCRYPTION_KEY=replace-with" in env_example, "PII key must be a non-secret placeholder")
    require("JWT_ACCESS_SECRET=replace-with" in env_example, "JWT access secret must be a placeholder")
    require("*.p12" in gitignore and "*.keystore" in gitignore, "Signing material must be ignored")
    require(".env" in gitignore and "!.env.example" in gitignore, "Local environment files must be ignored")

    print("Foundation validation passed: architecture, decisions, progress and secret hygiene are present.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"Foundation validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
