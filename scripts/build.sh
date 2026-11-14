#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
source scripts/env.sh
cmake -S . -B build/launcher -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PWD/build/sdk-install" \
    -DALICE_LAUNCHER_ONLY=ON -DALICE_DEVELOPMENT_BUILD=OFF
cmake --build build/launcher --target alice --parallel "${JOBS:-3}"
