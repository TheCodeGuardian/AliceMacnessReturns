#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
source scripts/env.sh
bash scripts/apply-sdk-patches.sh
export CPM_SOURCE_CACHE="$PWD/.tools/cpm"
export REX_MAX_JUMP_TABLE_ENTRIES=1024
export REX_REGISTER_SHARD_SPAN_BYTES=262144
project="$PWD/app"
sdk="$PWD/upstream/sa2-nx/sdk"
game="${1:-${ALICE_GAME_ROOT:-$PWD/assets/game_root}}"
python3 scripts/configure-game.py "$game"
(cd "$project" && "$sdk/out/mac-arm64/rexglue" codegen alice_manifest.toml)
cmake -S "$project" -B build/game -G Ninja -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_PREFIX_PATH="$PWD/build/sdk-install" -DREXGLUE_ENABLE_TRACY=OFF
cmake --build build/game --target alice --parallel "${JOBS:-6}"
