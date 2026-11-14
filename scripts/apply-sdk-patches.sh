#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
for patch in graphics-diagnostics swapchain-resize portable-sdk; do
    if git -C upstream/sa2-nx apply --reverse --check "../../patches/$patch.patch" 2>/dev/null; then
        continue
    fi
    git -C upstream/sa2-nx apply "../../patches/$patch.patch"
done
