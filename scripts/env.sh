# Source from the project root.
export PATH="$PWD/.tools/python/cmake/data/bin:$PWD/.tools/python/bin:$PATH"
mkdir -p "$PWD/.tools/tmp" "$PWD/.tools/clang-cache"
export TMPDIR="$PWD/.tools/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.tools/clang-cache"
export PYTHONDONTWRITEBYTECODE=1
