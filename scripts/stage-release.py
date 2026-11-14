#!/usr/bin/env python3
"""Stage the launcher and an offline build kit; never package generated game code."""
import hashlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "build/publication"
APP = STAGE / "packages/AliceMacnessReturns.app"
KIT = APP / "Contents/Resources/BuildKit"


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(".DS_Store", "__pycache__"))
    else:
        shutil.copy2(source, destination)


def port_sources(destination):
    port = ROOT / "app"
    for name in ("CMakeLists.txt", "overrides.toml", "src", "cmake", "macos"):
        copy(port / name, destination / name)


def licenses(destination):
    roots = {
        "ReXGlue": ROOT / "upstream/sa2-nx/sdk",
        "CPM": ROOT / ".tools/cpm",
        "CMake": ROOT / ".tools/python/cmake/data/doc/cmake",
        "Ninja": ROOT / ".tools/python/ninja-1.11.1.4.dist-info/licenses",
    }
    for name, source in roots.items():
        for file in source.rglob("*"):
            relative = file.relative_to(source)
            if any(part in {".git", "out", "__pycache__"} for part in relative.parts):
                continue
            lower = file.name.lower()
            if file.is_dir() and lower == "licenses":
                copy(file, destination / name / relative)
            elif file.is_file() and (lower.startswith(("license", "copying", "copyright", "notice", "ofl"))):
                copy(file, destination / name / relative)


def main():
    copy(ROOT / "build/launcher/app/alice.app", APP)
    port_sources(KIT / "project/app")
    copy(ROOT / "build/sdk-install", KIT / "sdk")
    copy(ROOT / ".tools/python/cmake/data/bin/cmake", KIT / "tools/bin/cmake")
    copy(ROOT / ".tools/python/cmake/data/share/cmake-3.31", KIT / "tools/share/cmake-3.31")
    copy(ROOT / ".tools/python/bin/ninja", KIT / "tools/bin/ninja")
    licenses(APP / "Contents/Resources/ThirdPartyLicenses")
    for source in (ROOT / "LICENSE", ROOT / "docs/THIRD_PARTY_NOTICES.md"):
        if source.is_file():
            copy(source, APP / "Contents/Resources" / source.name)
    digest = hashlib.sha256()
    for directory in (KIT / "project", KIT / "sdk", KIT / "tools"):
        for file in sorted(directory.rglob("*")):
            if file.is_file():
                digest.update(str(file.relative_to(KIT)).encode())
                digest.update(file.read_bytes())
    (KIT / "revision.txt").write_text("0.1.a-" + digest.hexdigest()[:16] + "\n")
    # Sign nested executables before sealing the outer app. Static archives are
    # linker inputs, not executable code objects and do not receive signatures.
    for file in sorted(KIT.rglob("*")):
        if file.is_file() and (file.suffix == ".dylib" or file.parent.name == "bin"):
            subprocess.run(["codesign", "--force", "--sign", "-", str(file)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(APP)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(APP)], check=True)
    print(APP)


if __name__ == "__main__":
    main()
