# The library lives in Application Support; the extension reads it through a read-only sandbox exception

The app (not sandboxed) owns the library and the wallpaper extension (sandboxed, as the extension point requires) has to read the optimised copies in it. The library lives in `~/Library/Application Support/Livepaper/`, and the extension's entitlements add `com.apple.security.temporary-exception.files.home-relative-path.read-only` for `/Library/Application Support/Livepaper/`. The app tells the extension what to show by replacing `render-state.json` in that folder and posting a Darwin notification; the extension answers with a Darwin notification whose 64-bit state is its heartbeat.

The M1 spike (S1, `Spikes/results/S1.md`, macOS 27.0) ran both candidates:

- **Application Support with the exception: works.** The extension listed the folder, read the config and played the file, with no sandbox denial and no prompt request in the log, under an ad-hoc and under a self-signed signature, and still did after a rebuild. The exception is a path in the sandbox profile, not tied to the signature, and it is not a restricted entitlement, so it needs no provisioning profile.
- **The extension's own container, written by the app: refused.** Without a Team ID the app's write fails within 10 ms with `NSCocoaErrorDomain 513`, and sandboxd logs `kTCCServiceSystemPolicyAppData … denied`: a refusal, not a prompt. This is Phosphene's route, and it works there only because its app and extension share a Team ID, which exempts them from App Data protection. App Groups are out for the same reason.
- **Darwin notifications work in both directions from inside the sandbox**, including `notify_set_state` / `notify_get_state`, so the heartbeat needs no file and the extension never writes anything the app has to read.

Consequences:

- The extension can read that one folder and nothing else. Every path it is given is relative to the library root and checked for containment (M2).
- Inside the sandbox the home-directory APIs return the container. The real home comes from `getpwuid`, in one place.
- "Temporary exception" entitlements would be questioned in App Store review. Livepaper does not ship there.
- Tested only through LaunchServices. The same write from a terminal succeeds, because TCC then holds the terminal responsible; that is a trap for anyone re-running the test, not a way out.

## Considered options

- **The extension's container.** Refused by TCC without a Team ID, as above.
- **App Groups.** Need a Team ID.
- **A security-scoped bookmark handed over XPC.** The app has no connection to the extension; only WallpaperAgent does.
- **`requestReadOnlyAccessTo:` on the agent's proxy.** Private, undocumented, untested; not needed since the exception works.
