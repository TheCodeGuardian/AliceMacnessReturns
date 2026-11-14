#!/usr/bin/env python3
"""Write a local ReXGlue manifest for a supported copy of the user's game."""
import hashlib
import json
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
game = Path(sys.argv[1]).expanduser().resolve()
xex = game / "default.xex"
if not xex.is_file():
    xex = game / "Default.xex"
if not xex.is_file() or not (game / "AliceGame").is_dir():
    raise SystemExit("Select extracted Xbox 360 files: default.xex and AliceGame/")
if hashlib.sha256(xex.read_bytes()).hexdigest() != "cb03c935a7b42982cbe00adf65cb700e976156eb7273c8ff63d6c87d419dd808":
    raise SystemExit("Unsupported media: expected Xbox 360 media 0B4C7F8F")
manifest = ("[project]\nname = \"alice\"\nsdk_version = \"0.10.0\"\ngame_root = " + json.dumps(str(game), ensure_ascii=False) +
            "\n\n[entrypoint]\nfile_path = " + json.dumps(str(xex), ensure_ascii=False) +
            "\nout_directory_path = \"generated/default\"\nincludes = [\"overrides.toml\"]\n")
(root / "app/alice_manifest.toml").write_text(manifest)
print("Configured user game; original files were not changed.")
