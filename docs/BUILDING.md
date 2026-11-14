# Building AliceMacnessReturns

Requires Apple Silicon, macOS 27+, Apple Command Line Tools (Clang and the macOS SDK), Git and Python 3 with pip. Initial dependency downloads require internet access. Scripts install tools only into the project directory; no system packages are installed.

## How the app is built

ReXGlue recompiles the Xbox 360 PowerPC code into C++. Apple Clang compiles that C++ for Apple Silicon ARM64. SDL3 provides the native window and input. ReXGlue runs the Xenos graphics runtime using Vulkan through MoltenVK, which maps Vulkan graphics to Apple's Metal API.

## Build the distributable app

```sh
bash scripts/bootstrap.sh
bash scripts/build-sdk.sh
bash scripts/build.sh
```

The output is `build/launcher/app/alice.app`. This launcher contains no translated game code. For a self-contained distributable app with the offline compiler kit, run:

```sh
bash scripts/build-release.sh
```

Publication outputs are under `build/publication`:

- `repository/`: the public project source.
- `packages/AliceMacnessReturns.app`: the ready-to-distribute app.
- `releases/0.1.a/`: app ZIP, project source, dependency source and checksums.

The app asks for the user's extracted Xbox 360 game and a separate data directory. Apple Command Line Tools must already be installed. First launch generates and compiles game code locally; later launches reuse the completed build. Build files are stored in `<data>/local-build/<revision>/`, outside the signed app. The game folder is read without copying or modifying it.

Only media `0B4C7F8F`, executable version 7, is supported. The wizard accepts a folder containing `default.xex` and `AliceGame/`, not an ISO. Game data and generated Alice code must not be included in public source or release packages.

## Build a local game app

After bootstrapping and building the SDK:

```sh
bash scripts/build-game.sh "/absolute/path/to/your/extracted/game"
bash scripts/run-game.sh
```

This validates the executable, generates code and builds `build/game/alice.app`. This locally generated app contains translated game code and is not the game-free release app. `JOBS=3` limits parallel compilation.

## Dependencies and rebuilding the runtime

CMake 3.31.6 and Ninja 1.11.1.4 are pinned in `.tools/python`. ReXGlue and dependency revisions are pinned in `scripts/bootstrap.sh` and its upstream dependency fetcher. Runtime compatibility patches are in `patches/`. Source and copyright notices for distributed libraries are provided in the dependency source archive and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The dependency source archive includes the patched SDK and its dependencies. To rebuild it, extract the archive, add CMake/Ninja to PATH and run from its root:

```sh
export CPM_SOURCE_CACHE="$PWD/cpm"
cmake -S sdk -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ -DREXGLUE_ENABLE_TRACY=OFF \
  -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON
cmake --build build --target rexglue rexgpu-xenos vulkan MoltenVK SDL3_test --parallel 3
cmake --install build --prefix "$PWD/sdk-install"
```

Use that SDK installation as `CMAKE_PREFIX_PATH` when configuring the app. The runtime is a replaceable dynamic library; modified LGPL decoder/runtime sources can be rebuilt and relinked without private signing keys. App bundles are ad hoc signed with `codesign --force --sign -`. The release is not notarized.
