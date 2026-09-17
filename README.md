# Livepaper

Live wallpapers for macOS. Give it a video and it becomes your wallpaper, on the desktop and the lock screen. Free, open source, no accounts, no marketplace, no telemetry.

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

## Layout

| Path | Holds |
|---|---|
| `App/` | The menu-bar app |
| `Gallery/` | Every design-system component in isolation, for review |
| `CLI/` | The `livepaper` command-line tool |
| `Packages/LivepaperKit/` | Core models and rules, import, playback, system services |
| `Packages/DesignSystem/` | Tokens and components |
| `docs/` | Roadmap, milestone specs, decision records |
| `CONTEXT.md` | The project's vocabulary |
| `.agents/skills/` | Agent skills used to build the project (`.claude/skills/` links to them) |

The skills come from [emilkowalski/skills](https://github.com/emilkowalski/skills), [mattpocock/skills](https://github.com/mattpocock/skills) and [jakubkrehel/make-interfaces-feel-better](https://github.com/jakubkrehel/make-interfaces-feel-better), all MIT-licensed. `skills-lock.json` records the exact versions.

## License

[MIT](LICENSE)
