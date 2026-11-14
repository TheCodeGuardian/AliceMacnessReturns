#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
source scripts/env.sh
mkdir -p upstream
if [[ ! -x .tools/python/cmake/data/bin/cmake || ! -x .tools/python/bin/ninja ]]; then
    python3 -m pip install --disable-pip-version-check --no-cache-dir --no-compile \
        --only-binary=:all: --target .tools/python cmake==3.31.6 ninja==1.11.1.4
fi
checkout() {
    local dir="upstream/$1" url="https://github.com/$2.git" rev="$3"
    if [[ ! -e "$dir" ]]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$url"
        git -C "$dir" fetch --depth 1 origin "$rev"
        git -C "$dir" checkout -q --detach "$rev"
    fi
    if [[ "$(git -C "$dir" rev-parse HEAD)" != "$rev" ]]; then
        echo "$dir: expected revision $rev; existing checkout preserved" >&2
        exit 1
    fi
}
checkout sa2-nx ChanseyIsTheBest/sa2-nx baf523b8e93a1b02d8b73d13aebf86780f8cc0c6
checkout rexglue-sdk rexglue/rexglue-sdk f5337cdc947ff6d4c4196737e2c807a48f2a1fc2
git -C upstream/rexglue-sdk submodule update --init --recursive --depth 1 --jobs 4
python3 upstream/sa2-nx/tools/fetch_thirdparty.py --source upstream/rexglue-sdk

bash scripts/apply-sdk-patches.sh
