#!/usr/bin/env python3
"""Create audited source/release packages using only explicit publication inputs."""
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "build/publication"
REPO = STAGE / "repository"
RELEASE = STAGE / "releases/0.1.a"
APP = STAGE / "packages/AliceMacnessReturns.app"
SOURCES = STAGE / "packages/dependencies-source"
EXCLUDED = {".git", "out", "__pycache__", ".DS_Store", ".codex", ".agents"}
GAME_EXT = {".iso", ".xex", ".upk", ".xxx", ".bik", ".xma", ".svod", ".xvd", ".gpd"}


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        target = os.readlink(source)
        if destination.is_symlink() and os.readlink(destination) == target:
            return
        destination.symlink_to(target)
    elif source.is_dir():
        destination.mkdir(exist_ok=True)
        for file in source.iterdir():
            if file.name not in EXCLUDED:
                copy(file, destination / file.name)
    else:
        shutil.copy2(source, destination)


def hash_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit(directory):
    count = total = 0
    for file in directory.rglob("*"):
        relative = file.relative_to(directory)
        generic_dependency_generated = "sdk" in relative.parts and "thirdparty" in relative.parts
        if any(p in {"game_root", "AliceGame", "screenshots", ".git", "notification-attachments"} for p in relative.parts) or ("generated" in relative.parts and not generic_dependency_generated):
            raise RuntimeError(f"Forbidden publication path: {file}")
        if file.is_symlink():
            if not file.resolve().is_relative_to(directory.resolve()):
                raise RuntimeError(f"Escaping symlink: {file}")
        if not file.is_file():
            continue
        upstream_editor_settings = file.name == "settings.json" and ".vscode" in relative.parts
        if file.suffix.lower() in GAME_EXT or (file.name in {"settings.json", "alice_manifest.toml"} and not upstream_editor_settings):
            raise RuntimeError(f"Game or user data found: {file}")
        if file.name.startswith(("alice_recomp.", "alice_register.", "alice_init.")):
            raise RuntimeError(f"Translated game source found: {file}")
        count += 1
        total += file.stat().st_size
    return {"files": count, "bytes": total}


def source_archive(folder, output):
    with tarfile.open(output, "w:gz", compresslevel=6) as archive:
        archive.add(folder, arcname=folder.name, recursive=True)


def main():
    if not (APP / "Contents/Resources/BuildKit/revision.txt").is_file():
        raise SystemExit("Run stage-release.py first")
    for name in ("README.md", "LICENSE", ".gitignore", "CMakeLists.txt"):
        copy(ROOT / name, REPO / name)
    for name in ("BUILDING.md", "THIRD_PARTY_NOTICES.md"):
        copy(ROOT / "docs" / name, REPO / "docs" / name)
    obsolete_notice = REPO / "THIRD_PARTY_NOTICES.md"
    if obsolete_notice.exists():
        obsolete_notice.unlink()
    for name in ("bootstrap.sh", "env.sh", "build.sh", "build-sdk.sh", "apply-sdk-patches.sh", "build-game.sh", "configure-game.py", "run-game.sh", "build-release.sh", "stage-release.py", "package-publication.py"):
        copy(ROOT / "scripts" / name, REPO / "scripts" / name)
    for name in ("graphics-diagnostics.patch", "swapchain-resize.patch", "portable-sdk.patch"):
        copy(ROOT / "patches" / name, REPO / "patches" / name)
    for name in ("CMakeLists.txt", "src", "cmake", "macos", "overrides.toml"):
        copy(ROOT / "app" / name, REPO / "app" / name)
    # Keep complete dependency source, excluding build outputs and Git history.
    copy(ROOT / "upstream/sa2-nx/sdk", SOURCES / "sdk")
    copy(ROOT / ".tools/cpm", SOURCES / "cpm")
    copy(REPO / "docs/BUILDING.md", SOURCES / "BUILDING.md")
    copy(ROOT / "upstream/sa2-nx/THIRD_PARTY_NOTICES.md", SOURCES / "sa2-nx-THIRD_PARTY_NOTICES.md")
    copy(ROOT / "upstream/sa2-nx/tools/fetch_thirdparty.py", SOURCES / "tools/fetch_thirdparty.py")
    copy(ROOT / "upstream/sa2-nx/LICENSE", SOURCES / "tools/LICENSE")
    # Exact upstream dependency revisions are useful even without .git directories.
    revisions = subprocess.check_output(["git", "submodule", "status", "--recursive"], cwd=ROOT / "upstream/rexglue-sdk", text=True)
    (SOURCES / "UPSTREAM_REVISIONS.txt").write_text(revisions)
    manifest = {str(file.relative_to(SOURCES)): hash_file(file) for file in sorted(SOURCES.rglob("*"))
                if file.is_file() and file.name != "SOURCE_MANIFEST.json"}
    (SOURCES / "SOURCE_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    executable = APP / "Contents/MacOS/alice"
    symbols = subprocess.check_output(["nm", "-g", str(executable)], text=True)
    if "PPCImageConfig" in symbols or "sub_82" in symbols:
        raise RuntimeError("The release executable contains translated game symbols")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(APP)], check=True)
    stats = {name: audit(path) for name, path in (("repository", REPO), ("app", APP), ("dependency_sources", SOURCES))}
    # The source snapshot must not expose local development paths or secrets.
    for file in REPO.rglob("*"):
        if file.is_file() and file.suffix != ".icns":
            data = file.read_bytes()
            if str(Path.home()).encode() in data or (b"/var/" + b"folders/") in data or (b"-----BEGIN " + b"OPENSSH PRIVATE KEY-----") in data:
                raise RuntimeError(f"Private development data: {file}")
    RELEASE.mkdir(parents=True, exist_ok=True)
    notes = """# AliceMacnessReturns 0.1.a

An unofficial native port of Alice: Madness Returns for Apple Silicon based on the Xbox 360 game

Experimental alpha for Apple Silicon / macOS 27. Includes a native setup wizard, Settings, a local Xbox achievement browser, macOS notifications, window resize fixes, SDL3 and a Vulkan/MoltenVK runtime. Graphics and performance remain under development.

The .app contains no original game files and no precompiled translated Alice code. You must supply your own extracted Xbox 360 game (media 0B4C7F8F, version 7) and Apple Command Line Tools. First launch compiles locally; subsequent launches reuse the result. No game files are downloaded. ISO files are not directly supported by the wizard.

The app is ad hoc signed, not notarized. The matching project source and dependency source archives are included. See the README and third-party notices before redistribution. Nothing has been uploaded to GitHub by this packaging process.
"""
    (RELEASE / "RELEASE_NOTES.md").write_text(notes)
    source_archive(REPO, RELEASE / "AliceMacnessReturns-0.1.a-source.tar.gz")
    source_archive(SOURCES, RELEASE / "AliceMacnessReturns-0.1.a-dependencies-source.tar.gz")
    subprocess.run(["ditto", "-c", "-k", "--keepParent", "--norsrc", str(APP), str(RELEASE / "AliceMacnessReturns-0.1.a.zip")], check=True)
    checksums = []
    for file in sorted(RELEASE.iterdir()):
        if file.name != "SHA256SUMS" and file.is_file():
            checksums.append(f"{hash_file(file)}  {file.name}")
    (RELEASE / "SHA256SUMS").write_text("\n".join(checksums) + "\n")
    report = """# Publication audit — 0.1.a

Prepared from an explicit source allowlist; no Git history was copied.

- No original Alice game directories, executable, disc images, packages, save files, achievement images, screenshots, logs, local settings or generated Alice source are included.
- The release app was built with ALICE_LAUNCHER_ONLY=ON. Its exported symbols contain neither PPCImageConfig nor translated sub_82* game functions. Its offline BuildKit contains only native project source, the generic SDK, CMake and Ninja.
- The application icon is the maintainer-provided silver apple/serpent icon, not extracted game art.
- Complete patched SDK/dependency source and license texts accompany the binaries. Upstream versions and per-file source hashes are in the dependency source archive.
- The app passes codesign --verify --deep --strict with an ad hoc signature. It is not notarized.
- Source files were checked for private developer home paths and private-key headers. The repository omits all local build/test history.
- Only the supported user-provided game can produce the locally compiled game bundle. That local bundle is outside this publication tree.

Automated path/symbol/license checks reduce accidental inclusion; they are not a legal opinion or a guarantee about third-party intellectual property.

Counts (uncompressed, including symlink targets):

""" + "```json\n" + json.dumps(stats, indent=2) + "\n```\n"
    (STAGE / "PUBLICATION_AUDIT.md").write_text(report)
    print(json.dumps(stats, indent=2))
    print(f"Publication files: {STAGE}")


if __name__ == "__main__":
    main()
