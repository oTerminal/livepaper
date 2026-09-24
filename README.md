# Livepaper

Live wallpapers for macOS. Give it a video or a Wallpaper Engine scene and it becomes your wallpaper, on the desktop and the lock screen. Free, open source, no account of its own, no marketplace, no telemetry. To get items from Wallpaper Engine's Workshop, it can sign in to your own Steam account.

**Status: early development. Nothing to install yet.** The plan and current milestone are in [docs/roadmap.md](docs/roadmap.md).

## Requirements

- macOS 26 or later, Apple Silicon
- To build: Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [SwiftLint](https://github.com/realm/SwiftLint)

## Building

```sh
brew install xcodegen swiftlint
make            # generate the Xcode project, lint, test, build
```

`make gen` writes `Livepaper.xcodeproj` from `project.yml`; the project file is not checked in. Open it in Xcode after generating.

| Command | Does |
|---|---|
| `make gen` | Generate the Xcode project |
| `make lint` | SwiftLint, including the design rules |
| `make test` | Swift Testing suites in both packages |
| `make build` | Build the app, the Gallery and the CLI |
| `make ffmpeg` | Build the ffmpeg helper from source (`Helpers/ffmpeg/`). The import tests that convert WebM, MKV, AVI, WMV and GIF are skipped without it |
| `make shader-tools` | Build the shader tools, glslang and SPIRV-Cross, from source (`Helpers/shader-tools/`). Import uses them to translate a scene's shaders to Metal, and the tests that translate shaders are skipped without them |

## Layout

| Path | Holds |
|---|---|
| `App/` | The menu-bar app |
| `Gallery/` | Every design-system component in isolation, for review |
| `CLI/` | The `livepaper` command-line tool |
| `Packages/LivepaperKit/` | Core models and rules, import, scenes, playback, system services, the Workshop |
| `Packages/DesignSystem/` | Tokens and components |
| `Helpers/ffmpeg/` | Build script, licences and notes for the bundled LGPL ffmpeg helper |
| `Helpers/shader-tools/` | Build script, licences and notes for the bundled shader tools |
| `docs/` | Roadmap, milestone specs, decision records |
| `CONTEXT.md` | The project's vocabulary |
| `.agents/skills/` | Agent skills used to build the project (`.claude/skills/` links to them) |

The skills come from [emilkowalski/skills](https://github.com/emilkowalski/skills), [mattpocock/skills](https://github.com/mattpocock/skills) and [jakubkrehel/make-interfaces-feel-better](https://github.com/jakubkrehel/make-interfaces-feel-better), all MIT-licensed. `skills-lock.json` records the exact versions.

## License

[MIT](LICENSE). The ffmpeg helper is a separate program under the LGPL, built from source by `Helpers/ffmpeg/build.sh`; see `Helpers/ffmpeg/README.md`. The shader tools are separate programs under permissive licences, built from source by `Helpers/shader-tools/build.sh`; see `Helpers/shader-tools/README.md` and [NOTICE](NOTICE).
