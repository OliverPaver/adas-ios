#!/usr/bin/env python3
"""Check the bundled model files against their recorded SHA-256 identities."""

import hashlib
import json
from pathlib import Path
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / "MODEL_MANIFEST.json").read_text())
    failed = False
    for entry in manifest["files"]:
        path = root / entry["path"]
        if not path.is_file():
            print(f"MISSING {entry['path']}")
            failed = True
            continue
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        ok = digest.hexdigest() == entry["sha256"] and path.stat().st_size == entry["bytes"]
        print(f"{'OK' if ok else 'MISMATCH'} {entry['path']}")
        failed |= not ok
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
