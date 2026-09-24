# M9: release engineering

Turn a green build into something a stranger can download, open and keep up to date, with the licences' notices beside it. Lane C, with M2 and M4. See `docs/roadmap.md` (Distribution, Telemetry, the M9 row, the Sparkle and translocation risks) and records 0001, 0003, 0004, 0006 and 0008; the evidence is `Spikes/results/S0.md`, `S0b.md`, `S0c.md` and `raw/s0b-package-dmg.txt`. Its inputs, records 0004 and 0006, are settled; it waits on M5-engine.md's extension identifier and entitlements file, M6-screens.md's bundled helper and M7-system-integration.md's samples.

## Rules

- Release scripts live in `Tools/release/`, prototyped by `Spikes/scripts/sign.sh`, `make-cert.sh` and `package-dmg.sh`, which are never called.
- Xcode never signs with the certificate: `project.yml` keeps `CODE_SIGN_IDENTITY: "-"` and `ENABLE_HARDENED_RUNTIME: NO` (record 0004), `sign.sh` re-signs the product, and only the tag job holds the certificate. M9 rewrites `project.yml`'s "Release signing (self-signed certificate) is set up in M9" comment to say so.
- Innermost first, the extension with its entitlements file before the app, the app last. Never `codesign --deep`, no hardened runtime, `--force --timestamp=none`.
- Secrets are the certificate's private key (a `.p12`), its password and Sparkle's EdDSA private key: each in the owner's password manager and as a secret of the GitHub `release` environment, nowhere else, never echoed, never in an artefact or the repo, no step holding one under `set -x`; `.gitignore` already refuses `*.p12`, `*.key` and `*.dmg`.
- Every release script takes `--dry-run`: every step but publishing, with the ad-hoc identity and a throwaway key.
- The version is set in `project.yml` and nowhere else. Pure logic goes test-first into a `ReleaseKit` library (`Tools/release/Package.swift`, a third `swift test` line in the Makefile), except `installDecision`, in `LivepaperCore` for the app to call; the shell is proved by the dry run and the rehearsal.

## What earlier milestones settled

- The certificate keeps the designated requirement stable across a rebuild (`identifier … and certificate leaf = H"6741…3de7"`), where ad-hoc gives a fresh `cdhash` every build (`S0c.md`, 0004). Gatekeeper keys on it; nothing has to trust it. The login item follows the bundle, staying `enabled` when the app is replaced.
- A quarantined download ran, extension included, after Open Anyway alone, no `xattr`; `spctl --assess` says `rejected`, `origin=` the certificate's name (`raw/s0b-package-dmg.txt`). The spike's DMG, 568K, made `hdiutil create` print the notice naming `diskutil image create` (`raw/s0b-package-dmg.txt`).
- The extension's entitlements are the sandbox plus the read-only library exception (0001, 0002); the wallpaper store keys the user's choice by its bundle identifier and kept it through re-signing, moving and updating (0003).
- Replacing the bundle kills the running extension once, with nothing to restart it; the launch ladder (`judgeHeartbeat`, `allowAgentRestart`, M5-engine.md's "Hazard") brings it back, and an update is that sequence (0001). The library and render state in `~/Library/Application Support/Livepaper/` are untouched (0002).
- The helper's `out/` (`ffmpeg`, its source archive, `BUILD-INFO.txt` with `binary-sha256`, `build.sh`, `licenses/`) is CI's `ffmpeg-helper-arm64` artefact (M4-import.md); M6-screens.md bundles the binary, M9 publishes `out/`.
- The shader tools' `out/` (`glslang`, `spirv-cross`, their source archives, `BUILD-INFO.txt` with each binary's sha256, `licenses/`) is CI's `shader-tools-arm64` artefact (record 0008). `project.yml` bundles both next to the app's executable with an ad-hoc signature, which `sign.sh` replaces (M11-wallpaper-engine-scenes.md, "As built"). steamcmd is never bundled: the app fetches it from Valve on first use (record 0009), so `sign.sh` and the notices leave it out.
- The app is not sandboxed, so Sparkle's sandboxing XPC services are not needed; `Package.resolved` is git-ignored, so a package must be pinned exactly.
- Wallper 1.11.2 has no Sparkle key at all and still ships Sparkle's mach names in its entitlements; how it updates was not observable, which is why `verify.sh` reads our own entitlements rather than trusting them (`docs/research/wallper.md`).

## Parts

| Part | Lives in | Does |
|---|---|---|
| Signing | `make-cert.sh`, `sign.sh`, `designated-requirement.txt` | Certificate made once by hand, never in CI: `openssl`, `Livepaper Release`, ten years. Its `.p12` (base64) and password are the secrets `LIVEPAPER_SIGNING_P12` and `..._PASSWORD`; both designated requirements are committed. `sign.sh <app> --identity <name\|->` follows `signingOrder` over the bundle's Mach-O listing: Sparkle's helpers and XPC services, its framework, the ffmpeg helper, the shader tools (`glslang`, `spirv-cross`, record 0008), the CLI if M7-system-integration.md bundles it, the extension with its entitlements file, the app. Refuses `--deep`, an unrecorded leaf hash and a Mach-O it missed; ends in `codesign --verify --strict` and `--verify -R` |
| Versioning | `project.yml`, `ReleaseKit.Version` | `MARKETING_VERSION` is `X.Y.Z`, `CURRENT_PROJECT_VERSION` an integer rising by one per release in the same commit, both in `settings.base`. Sparkle orders updates by `CFBundleVersion`, so that is what climbs. The tag is `v` plus `MARKETING_VERSION`; nothing else starts a release |
| DMG | `package.sh`, `verify.sh` | `Livepaper-<version>.dmg`, compressed, volume `Livepaper`: the app, an `Applications` symlink and `Licenses/`. No background picture. `diskutil image create` (0004), `hdiutil create` until the dry run shows `macos-26` has it. Plus `Livepaper-<version>.zip` (`ditto -c -k --keepParent`) for Sparkle. Budget: 50 MB. `verify.sh` mounts it and checks the signature and the requirement, the extension's entitlements being those two keys and no more, the helper's sha256 against `BUILD-INFO.txt` and each shader tool's against its own, the samples and `Licenses/` present, the zip matching the DMG's cdhash, and `pluginkit -m -v -p com.apple.wallpaper` after a local install |
| Sparkle | `project.yml`, `App/`, the app's `Info.plist`, `sparkle.env` | Sparkle 2 as a Swift package pinned exactly, not a framework in master's history. `SUFeedURL`, `SUPublicEDKey`, checks once a day, `SUEnableSystemProfiling` off, download and install waiting for a click. Sparkle's own unstyled windows through `SPUStandardUpdaterController`, "Check for Updates…" where M6-screens.md puts Settings, its tools from that version's archive, sha256 in `sparkle.env`. `generate_keys` makes the EdDSA pair once: public key in `Info.plist`, private key the secret `SPARKLE_ED_PRIVATE_KEY`, read by `generate_appcast` from a file that lives for that step. No deltas in 1.0 |
| Appcast | The orphan `appcast` branch on GitHub Pages, `appcast.sh`, `CHANGELOG.md` | One `appcast.xml` for the app's life at a fixed `https` URL, readable without a GitHub account, on an orphan branch as `pr-media` is, since a release asset would move. One entry per release: version, build, enclosure URL and length, EdDSA signature, and the `## X.Y.Z` section of `CHANGELOG.md`, which is also the release body. A build already in the feed, or a missing section, stops it |
| Workflow | `.github/workflows/release.yml`, `release.sh` | On a `v*` tag, on `macos-26`, in the `release` environment: `ffmpeg` and `shader-tools` as in `ci.yml`, gen, the tag checked against `project.yml`, a Release build, the `.p12` into a run-scoped keychain deleted even on failure, `sign.sh`, `package.sh`, `verify.sh`, `generate_appcast`, the appcast branch, then a release of the DMG, the zip, `ffmpeg-helper-arm64.zip` and the ffmpeg source archive alone, so the notice can link it (0006). It refuses a wrong tag, a build not above the appcast's last, an existing release, an ad-hoc or foreign signature, a missing secret, and whatever `verify.sh` refuses. `release.sh --dry-run` (`make release-dry-run`) is the same into `build/release/`. Manual: the certificate, the key, the changelog, the rehearsal |
| First launch | `LivepaperCore.installDecision`, `App/` | Runs before anything is registered; M7-system-integration.md's onboarding waits for it. The app asks `SecTranslocateIsTranslocatedURL` and hands that, the path and the volume's writability to the decision, with `/AppTranslocation/` in the path as the fallback. Translocated or read-only, Open Applications Folder and Quit: "Livepaper was opened from the disk image. Drag it to the Applications folder, then open it from there." Writable but outside `/Applications` and `~/Applications`, Move and Not Now: "Livepaper works best in the Applications folder. Move it there now?" Move relaunches from the new path; Not Now is remembered per path |
| Notices | `LICENSE`, `NOTICE`, `Licenses/` on the DMG, `Credits.rtf`, `README.md` | One text from one source in three places: MIT; Phosphene (`NOTICE`, M5-engine.md); Sparkle's licence; the helper's LGPL notice with its version, source-archive link, sha256 and how to replace the binary; glslang's and SPIRV-Cross's notices with their versions and licence texts (`Helpers/shader-tools/licenses/`, record 0008); the samples' CC0 provenance from `PROVENANCE.md`. `Licenses/` holds the texts, the About panel `Credits.rtf`. The README adds the Open Anyway steps, no `xattr` (0004), why it is not notarized, the requirement in full, and that Homebrew is not relied on (roadmap) |

## Seams for test-first work

| Seam | Tested as |
|---|---|
| Signing order | Pure: a bundle's file listing to the list to sign. Deepest first; the extension before the app with its entitlements path; the app last; a Mach-O left unlisted fails |
| Requirement match | Pure: `codesign -d -r-` output to identifier and leaf hash; the recorded file passes, the `cdhash` form and another leaf fail |
| Version rules | Table: `v1.0.0` matches `1.0.0`; `1.0.0`, `v1.0` and `v1.0.0-beta.1` start nothing; build 12 after 12 refused, 13 accepted |
| Appcast and notes | Pure: an entry from its parts, and the `## X.Y.Z` section of a changelog; merging keeps older entries, orders by build, refuses a duplicate; a missing, empty or doubled section fails |
| Install decision | Table: `/Applications/…` and `~/Applications/…` proceed; translocated or read-only asks for the drag; `~/Downloads/…` offers the move; Not Now binds to that path only |
| Notices | Pure: the text names the ffmpeg version, its source link and sha256, Sparkle's version, Phosphene, glslang's and SPIRV-Cross's versions and every sample; a gap fails |

## Release rehearsal

On the tagged build, except R1 and R3. The second Mac must never have seen the project or its certificate; M1-engine-spike.md's S0b checklist becomes the product's, its step 5 now a sample loop playing on the desktop and the lock screen.

| # | Check | Pass when |
|---|---|---|
| R1 | Dry run on a pull request | The `check` job makes the DMG, the zip and an appcast entry with the ad-hoc identity, publishing nothing |
| R2 | Tag `vN` | The release has its four files and notes; `verify.sh` passed in the log; `codesign -d -r-` on the downloaded app matches both requirements; the appcast keeps older entries and `curl` fetches it with no account; `Licenses/`, the About panel and the README carry the same text, its source link resolving to the pinned sha256 |
| R3 | Quarantine and translocation | With a real download's attribute (`xattr -p` on one, `xattr -w com.apple.quarantine` onto the DMG): from the mounted image it shows the drag prompt and registers nothing; after the drag and Open Anyway it runs; from `~/Downloads`, Move puts it in `/Applications` and relaunches there |
| R4 | Second Mac, fresh | All eight checklist steps: after Open Anyway alone a sample plays on the desktop and the lock screen; `pluginkit` lists the extension under `/Applications`; the login item reads on; likewise after the reboot |
| R5 | N to N+1 through Sparkle | With `vN` live on the second Mac: Check for Updates finds `vN+1`, installs, relaunches; no second Open Anyway; the wallpaper live again without a click inside the ladder's grace plus one step (M5-engine.md, "Hazard"); login item on; assignments and library intact; System Settings still shows Livepaper; the requirement unchanged |
| R6 | Refusals | Each refusal the Workflow row lists is provoked once: the reason logged, nothing published |
| R7 | Secrets | No key material in the workflow log, the run's keychain gone, no artefact holding a key |

The PR shows (CLAUDE.md) the "Apple could not verify" dialog, the Privacy & Security pane and both install prompts as screenshots; the Sparkle update, from Check for Updates to the wallpaper coming back, as a GIF with its MP4; and R4 and R5 filled in from the second Mac's macOS build. M10-1.0.md repeats them per seed.

## Done when

- `make gen build test lint` is green with `ReleaseKit`'s tests, the dry run is green in CI, and every rehearsal row passes, R4 and R5 against a real download from a real release.
- `designated-requirement.txt` is committed and matches the tagged build, and the README's steps are the ones the second Mac's user followed.
- An "As built" section, as M4-import.md's: the Sparkle version, which image command shipped and its line, the DMG's size, the feed URL, and what R5 showed about quarantine on the update.

## Out of scope

Onboarding, the login item toggle and the CC0 samples with `Resources/Samples/PROVENANCE.md` (M7-system-integration.md; M9 only verifies they ship inside the budget). The Check for Updates and About screens, and bundling the helper (M6-screens.md). The soak and the energy numbers (M8-hardening.md). The beta-seed checklist, the 1.0 tag, a beta channel and delta updates (M10-1.0.md). Notarization, needing a paid account (roadmap). A Homebrew cask.
