#!/usr/bin/env python3
"""Create the project-root build.json using the engine version macros."""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[1]
VERSION_HEADER = PROJECT_ROOT / "src" / "engine.hpp"
BUILD_MANIFEST = PROJECT_ROOT / "build.json"
PROJECT_NAME = "Diggers"
VERSION_MACROS = ("VER_MAJOR", "VER_MINOR", "VER_BUILD", "VER_REV")


def read_engine_version() -> list[int]:
    try:
        source = VERSION_HEADER.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError(f"Cannot read engine version header {VERSION_HEADER}: {exc}") from exc

    values: dict[str, int] = {}
    for line_number, line in enumerate(source.splitlines(), start=1):
        match = re.match(
            r"^\s*#\s*define\s+(VER_[A-Z_]+)\s+([0-9]+)(?:\s|$)", line
        )
        if not match:
            continue
        name, raw_value = match.groups()
        if name not in VERSION_MACROS:
            continue
        if name in values:
            raise RuntimeError(f"Duplicate {name} definition at {VERSION_HEADER}:{line_number}")
        values[name] = int(raw_value)

    missing = [name for name in VERSION_MACROS if name not in values]
    if missing:
        raise RuntimeError(
            f"Missing version macro(s) in {VERSION_HEADER}: {', '.join(missing)}"
        )
    return [values[name] for name in VERSION_MACROS]


def write_manifest(version: list[int]) -> None:
    content = {
        "Version": 1,
        "Project": PROJECT_NAME,
        "Engine": version,
    }
    serialized = json.dumps(content, separators=(",", ":")) + "\n"
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{BUILD_MANIFEST.name}.", suffix=".tmp", dir=PROJECT_ROOT
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(serialized)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, BUILD_MANIFEST)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def main() -> int:
    try:
        version = read_engine_version()
        write_manifest(version)
    except (OSError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"Wrote {BUILD_MANIFEST.relative_to(PROJECT_ROOT)}: {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
