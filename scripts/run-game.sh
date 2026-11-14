#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
exec "$PWD/build/game/alice.app/Contents/MacOS/alice" "$@"
