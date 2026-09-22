# Wallper, observed from outside

Wallper 1.11.2 (`sandimax.Wallper`, Xcode 26.6 / SDK 26.5, minimum macOS 14.6), observed 2026-09-22 on macOS 27.0 (26A428), arm64. Times are local, UTC+1 (Europe/Dublin; `date` prints "IST", meaning Irish, not Indian).

Observed statically (bundle metadata, `codesign`, `otool -L`, entitlements, the DMG, the files and preferences it left in `~/Library`) and from the unified log of its two sessions of 2026-09-21. **It was not launched for this note and did not run at all on 2026-09-22**: zero `process == "Wallper"` entries all day, and WallpaperAgent has held one pid since 2026-09-21 20:30. Wallper logs nothing itself, so every claim rests on system log lines, files, preferences or bundle metadata. Claims resting only on the binary's string table were removed, leaving those questions marked not observable. Extends record 0003, corrects it in sections 1 and 4.

## 1 Selection without System Settings

It turns the user's video into an Aerial. Four writes land in the same second (2026-09-21 20:15:04): a `.mov` and a `.png` into Apple's `~/Library/Application Support/com.apple.wallpaper/aerials/`, an added asset in that folder's `manifest/entries.json`, and the wallpaper store. The slot is one fixed UUID, held twice in its preferences, and a new wallpaper overwrites the same file, so Apple's manifest gained exactly one asset (165 where Apple shipped 164). Its files are mode 644 where Apple's are 600.

The store is written whole and small (607 B): `SystemDefault` and `AllSpacesAndDisplays`, each with a `Desktop` and an `Idle` entry, all four naming `com.apple.wallpaper.choice.aerials` with the slot as configuration, `Displays` and `Spaces` left empty. The screen saver is therefore selected too, and one asset covers every display and Space. It then restarts WallpaperAgent and quits System Settings by Apple event, costing a TCC Automation prompt. The restart is a burst, not one `killall`: six inside 80 ms kill the extension, then the agent, then the agent launchd respawned 13 ms earlier, so launchd backs off a second. The aerial is live 1.1 to 1.6 s after the burst begins. The selection holds: with Wallper absent all day, WallpaperAgent refreshed the store's `LastUse` at 11:27 today and all four entries still name the slot.

Only public frameworks are linked and the bundle holds no wallpaper extension. Its one private-framework route is Apple's MediaRemote, via a bundled Perl adapter and a zipped helper framework in `Resources`. It also ships its own copy of Apple's aerial manifest (152 assets against the user's 165), which a restore feature would overwrite. **Not observable:** the repair routine's triggers and frequency; a desired-asset-ID preference is the state it would need, but no repair appeared in a day of logs.

```
prefs: wallper.lockscreen.slot.uuid = ls27DesiredAssetID = A469986C-9E9C-42F4-B2AF-51C1C429D713
Index.plist (607 B): {SystemDefault, AllSpacesAndDisplays} x {Desktop, Idle} -> choice.aerials;
  LastSet 2026-09-21 19:15:04Z; LastUse 2026-09-22 10:27:10Z; Displays {} Spaces {}
20:15:04.553 killall -> extension; .563 killall -> agent[44320]; .571 spawned [50507]
  .582 killall -> [50507] "ran for 13ms"; .583 launchd "Pushing respawn out by 1 seconds"
20:15:05.596 spawned [50520]; .716 BEGIN Acquire Wallpaper [.extension.aerials]
20:06:57.86 System Settings Apple Events eventID 1903520116 ('quit'), via appleeventsd+TCC
```

## 2 Launch and quit

Quit touches nothing: both sessions ended in a normal AppKit termination in 16 ms, and the store, manifest and slot file still carry their 20:15:04 timestamps. What stays on the desktop is Apple's Aerials extension holding the slot `.mov` at rest; which frame was not observed. **It never restores the previous wallpaper:** the store still named the aerial a day later, and its only exits are its own restore feature and System Settings. Record 0003 saw the desktop as a borderless window of its own above the system wallpaper window, which nothing here contradicts. **Not observable:** what it does at launch beyond LaunchServices registration, the login-item sync and its status items.

```
20:17:14.529 Wallper[49029] AppKit Attempting sudden termination ... .545 Termination complete
stat: entries.json, aerials/videos/<slot>.mov, Index.plist all still "Sep 21 20:15:04"
```

## 3 Login item

`SMAppService` on the main app: no `Contents/Library/LoginItems`, no LaunchAgent plist anywhere. It read the status twice at launch, registered 24 s in, read back enabled 9 s later; later launches read status first and sync the toggle to it. `backgroundtaskmanagementd` records it as item type 2, an app. **The needs-approval state was never reached here:** only status 3 (not found) and 1 (enabled) occurred, never 2, so that UI was not seen. `sfltool dumpbtm` needs root, skipped.

```
20:06:06.191 SMAppService status: 3; 20:06:29.379 Register error: 0; 20:06:38.933 status: 1;
  20:13:11.996 [49029] status: 1 first thing on the second launch.  prefs: startOnLogin = 1
20:06:06.255 backgroundtaskmanagementd noteUseOfItemWithIdentifier: 2.sandimax.Wallper
```

## 4 Updates and distribution

**No Sparkle.** No `SUFeedURL`, no `SUPublicEDKey`, no `SU*` key at all in `Info.plist`; no `Contents/Frameworks`, no XPC services, no helpers. The one trace is two `mach-lookup` temporary-exception entitlements whose names follow Sparkle's XPC helper convention (`-spks`, `-spki`) with no Sparkle to use them, so the entitlements carry dead weight. Signing is otherwise clean: Developer ID, hardened runtime, notarized with the ticket stapled, universal, not sandboxed, with an embedded provisioning profile for iCloud key-value storage. The installed copy still carries its Chrome quarantine attribute and launches anyway, which a stapled ticket buys. The DMG is a plain 15 MB zlib drag layout. **Not observable:** the in-app updater and any translocation handling; no update ran while it was watched and no updater cache exists.

```
codesign: flags=0x10000(runtime); Developer ID: Dmytro Katyukha (P9X95TTA7H); Ticket=stapled;
  spctl accepted; stapler validate worked
entitlements: apple-events, network.client/server, files.user-selected.read-only, ubiquity-kvstore,
  mach-lookup ...-spks/-spki; no app-sandbox.  Info.plist: 27 keys, none beginning SU
xattr: quarantine ...;Chrome.  DMG: UDIF zlib 14.9 MB, Applications -> /Applications
```

## 5 URL schemes, Services, document types, CLI, helpers

One URL scheme, `wallper`. No `NSServices`, `CFBundleDocumentTypes`, `PlugIns`, `Extensions` or `XPCServices`, no command-line tool, and no `LSUIElement`: it is a Dock app that also owns menu-bar status items, confirmed by MenuBarAgent registering two `com.apple.appkit.status-items` scenes at launch. It declares an Apple Events usage string naming Music and Spotify and drives System Settings by Apple event (section 1), so Automation consent sits on its critical path. It also registers for iCloud key-value sync, caches a licence verdict, and ships ten localisations.

```
Info.plist: CFBundleURLSchemes ["wallper"]; no LSUIElement, NSServices, CFBundleDocumentTypes
20:06:06.52 MenuBarAgent Registered new scene: com.apple.appkit.status-items [Wallper] (x2)
```

## 6 Energy and pause preferences

Its preferences record exactly two pause causes and one quality lever: paused by hand, paused because of battery, and reduce quality on battery (off here, resolution native, quality high). Playback state is kept per display. A CPU-load or fullscreen pause rule is **not corroborated**: no such preference key exists and no such behaviour was seen, and Low Power Mode leaves no trace. **Idle CPU was not measured**, the app not being started. The log shows the cost shape: four AVPlayer consumers in the first session's opening minute, five in the second, for two displays.

```
prefs: wasManuallyPaused, wasPausedDueToBattery, reduceQualityOnBattery = 0; maxVideoResolution
  = native; videoQuality = high; LastWallpaperPlaybackStates [{screenID 1, isPlaying 1}]
log: FigPlayerResourceArbiterRegisterConsumer ... AVPlayer.43722-{1,3,4,5}
```

## 7 Multiple displays and how displays are identified

Wallper keys its per-display assignments by `screenID`, the `CGDirectDisplayID` as a string ("1" and "3" here), with a `screenIndex` and the CDN URL applied. WallpaperAgent, in the same minutes, names those displays by stable UUID. A `CGDirectDisplayID` is reassigned across reboots and hot-plugs, so the two identifiers do not survive equally. The lock screen gets no per-display treatment: one slot, one asset, `Displays` and `Spaces` empty.

```
prefs LastAppliedWallpapers: [{screenID "3", screenIndex 1, url cdn.wallper.app/...mp4, appliedAt
  1790017611}, {screenID "1", screenIndex 0, ..., appliedAt 1790018098}]
20:06:58.839 WallpaperAgent Create new wallpaper in runtime: display 1ED56131-... / 37D8832A-...
```

## 8 Sleep and wake

**Not observable.** Neither watched session contained a sleep or a wake, and Wallper emits nothing to the unified log, so there is no evidence either way. The roadmap's note that it has regressed three times on "playback not resuming after sleep" comes from its issue history, not from anything seen here.

## 9 Library, conversion, metadata, dedupe

`~/Library/Application Support/Wallper/` holds `library-metadata.json` (1.3 MB, caching the marketplace catalogue: 67 official and 2821 user-generated entries), `Previews/` (39 stills), `Videos/` (empty), and `LockScreenCache/` (2 transcodes). **The desktop plays straight from the CDN URL and keeps no local copy**; only the lock-screen transcode lands on disk, and it is copied verbatim into Apple's aerial slot, byte-identical by SHA-256. Re-conversion is skipped by a size-and-mtime signature kept per video in preferences. Playlists and a shuffle queue (enabled, auto-advance, current index) live in preferences, not in the library file. **Not observable:** the basis of its duplicate check, and the conversion strategy.

```
shasum -a 256: LockScreenCache/1d00614c-....mov == aerials/videos/A469986C-....mov (24ed0b97...)
prefs: LockScreenCache.sig.1d00614c-... = "13938475-1790018101.241232" (bytes-mtime);
  Playlists.items, ShuffleQueue.{isEnabled,autoAdvance,currentIndex}
```

## 10 Onboarding

Visible without launching: seven full-screen slide images in `Resources`, a completion flag and a seeded default playlist in preferences. The first run's shape is legible from the log: launch 20:06:05, notification centre a second later, login item registered 20:06:29, first wallpaper applied 20:06:51, so 46 s to a live wallpaper. **Not observable:** the wording and order of the steps, and whether the login-item and notification prompts belong to the flow, the UI not being opened.

## What this means for Livepaper

- M6: Wallper keys per-display state by `CGDirectDisplayID`, reassigned across reboots and hot-plugs, where the agent uses UUIDs. Livepaper's UUID keys already match the agent.
- M6: it streams from a CDN and keeps no desktop copy, so its library browses someone else's catalogue, not the user's.
- M6: its assignments and playlists live in preferences. Livepaper's versioned manifest survives a migration.
- M7: `SMAppService` went straight to enabled and requires-approval never occurred, the case nobody tests by accident. Wallper re-syncs its toggle from real status every launch.
- M7: a URL scheme and nothing else: no Services entry, document types, hotkeys or CLI.
- M7: quitting System Settings by Apple event costs a TCC Automation prompt on first run.
- M7: seven onboarding slides and 46 s to a live wallpaper is a bar to beat, not match.
- M7: it logs nothing to the unified log, so a bug report carries no evidence. Diagnostics need `os_log` with its own subsystem from the first shipping milestone.
- M8: two pause causes, each a separately remembered flag. One pure `decidePlayback` avoids that state.
- M5, M7: six `killall`s inside 80 ms make launchd kill a 13 ms old agent and back off a second. Both agent restarts, the watchdog's and the store edit's, send one signal, then wait. M8 drills it.
- M9: no Sparkle, no update signing key, and Sparkle's mach-lookup exceptions left unused in entitlements.
- M10: it depends on two undocumented Apple files and ships a stale copy of one. Livepaper touches only the store, twice (record 0003), so the checklist watches one.
