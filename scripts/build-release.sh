#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
bash scripts/build.sh
python3 scripts/stage-release.py
python3 scripts/package-publication.py
