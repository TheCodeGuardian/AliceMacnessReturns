# Third-party notices

AliceMacnessReturns is an unofficial port by TheCodeGuardian. Project code is supplied under GPL-3.0 (see LICENSE); upstream copyright and license notices remain applicable to their respective files. No license to Alice: Madness Returns or its materials is granted.

## Provenance

- [sa2-nx](https://github.com/ChanseyIsTheBest/sa2-nx), commit `baf523b8e93a1b02d8b73d13aebf86780f8cc0c6`: only its `sdk/` runtime/code generator and dependency fetch script are used. The SDK is BSD-3-Clause; its third-party code retains its own terms. Other sa2-nx application/rendering code is not bundled.
- [ReXGlue](https://github.com/rexglue/rexglue-sdk), BSD-3-Clause, based on [Xenia](https://github.com/xenia-project/xenia), BSD-3-Clause, and their contributors. The sa2-nx fork is based on SDK 0.10.0. The dependency fetch tree is pinned to `f5337cdc947ff6d4c4196737e2c807a48f2a1fc2`; fetched versions are recorded in the dependency source package. Local changes are supplied as three patches and as the complete patched SDK source.
- [SDL3](https://github.com/libsdl-org/SDL), zlib. The SDK uses its pinned SDL3 dependency.
- CMake 3.31.6, Kitware and contributors, BSD-3-Clause and bundled notices; Ninja 1.11.1 (Python distribution 1.11.1.4), Apache-2.0. Both executables are bundled for offline local compilation; Apple Clang and the macOS SDK are supplied by the user, not redistributed.

## Runtime and build-kit dependencies

ReXGlue includes FFmpeg (LGPL-2.1-or-later, GPL/nonfree components disabled), libmspack (LGPL-2.1), fmt (MIT), spdlog (MIT), simde (MIT), toml++ (MIT), CLI11 (BSD-3-Clause), inja (MIT), glslang (its composite BSD/MIT/Apache notices), SPIRV-Tools and SPIRV-Headers (Apache-2.0), Vulkan Headers/Loader and VulkanMemoryAllocator (Apache-2.0/MIT as identified in their files), MoltenVK (Apache-2.0), SPIRV-Cross and cereal (their Apache/MIT/BSD notices), Dear ImGui (MIT), xxHash (BSD-2-Clause), o1heap, aes128, disasm, stb, utf8cpp, disruptorplus and RenderDoc headers under their original licenses. The dependency source archive and bundled `ThirdPartyLicenses` retain the actual license texts and copyright notices; those texts govern each component.

The SDK runtime remains a replaceable dynamic library. Complete patched runtime and decoder sources, build scripts and compiler settings are supplied with the release so modified LGPL components can be rebuilt and relinked. See `docs/BUILDING.md` and the dependency archive's `SOURCE_MANIFEST.json`. No signing keys are required for the ad hoc build.

The silver apple/serpent application icon was provided by the project maintainer as `silver_apple_serpent_no_frame.icns`, SHA-256 `3f1c883e3624da82047b682ddc4963ac036b97b142d9455149af5e7f89136734`. Achievement images and descriptions are read from the user's own game at runtime and are not bundled.
