# AliceMacnessReturns

An unofficial native port of Alice: Madness Returns for Apple Silicon based on the Xbox 360 game

> [!IMPORTANT]
>
> **AliceMacnessReturns is an unofficial community project. It is not affiliated with Electronic Arts, Spicy Horse, Microsoft, or the Alice brand. Alice: Madness Returns and American McGee’s Alice are trademarks of Electronic Arts Inc.**
>
> **This is a native port with a local recompilation workflow. No game files are included or distributed, including precompiled translated game code.** AliceMacnessReturns requires your own legally obtained Xbox 360 copy of the game. Game assets and disc images are not distributed.

## How It Works

AliceMacnessReturns runs a native Apple Silicon application and builds the translated game code locally from games files selected by the user. App translates the game's PowerPC code into C++, and that C++ compiles to native arm64 using SDL3, ReXGlue and MoltenVK.

On first launch, the user selects an extracted game and a separate data folder. Later launches reuse the completed build. Build progress and a log are available. The original game folder is read, not modified. Game saves, caches, and the local build stay in the data folder chosen by the user.

## Requirements

- Apple Silicon Mac, obviously, with macOS 27.0 or later.
- An extracted Xbox 360 copy of the game. ISO is not supported by the setup wizard. Currently app supports only executable version 7 (only media 0B4C7F8F). Yours XEX SHA-256 must be: `cb03c935a7b42982cbe00adf65cb700e976156eb7273c8ff63d6c87d419dd808`
- Apple Xcode Command Line Tools, including Clang and the macOS SDK. Install them before starting setup if they are missing.
- 10+ GB of free space on your Mac.

## How to Play

1. Download `AliceMacnessReturns-0.1.a.zip` from [Releases](https://github.com/TheCodeGuardian/AliceMacnessReturns/releases).
2. Extract the app and place it in a writable location such as Applications.
3. Launch the app.
4. Complete setup with the wizard.
5. Play the game.

macOS may require approval in Privacy & Security for an app downloaded from the internet. See [Apple's instructions](https://support.apple.com/102445). Do not disable Gatekeeper globally, it is not safe for you.

## Features

- Achievement tracking using Xbox 360 metadata from your game and local progress.
- Window resize support.
- Settings menu (V-Sync, mute, macOS notifications, fullscreen).
- macOS Game Mode support.
- macOS notifications for achievements and menu events.

## Tests

Only tested on MacBook Air M4. That is not bad! But there is a lot of work… A complete playthrough has not been validated.

## Build from source

Developer setup and build instructions are in [docs/BUILDING.md](docs/BUILDING.md). The release launcher includes an offline build kit. Rebuilding the runtime is only needed when developing the app or changing its dependencies.
