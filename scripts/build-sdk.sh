#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
source scripts/env.sh
export CPM_SOURCE_CACHE="$PWD/.tools/cpm"
sdk=upstream/sa2-nx/sdk
cmake -S "$sdk" -B build/sdk -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DREXGLUE_ENABLE_TRACY=OFF -DCMAKE_INSTALL_PREFIX="$PWD/build/sdk-install" \
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON
cmake --build build/sdk --target rexglue rexgpu-xenos vulkan MoltenVK SDL3_test --parallel "${JOBS:-6}"
"$sdk/out/mac-arm64/rexglue" --help

cmake --install build/sdk --prefix "$PWD/build/sdk-install"
