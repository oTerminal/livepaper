## S0b: the downloaded build on a second Mac (gate G1)

Reported by Vaibhav, 2026-09-17. Build: `Livepaper-spike-20260917152856-selfsigned-plain-S1.dmg`
(self-signed, no hardened runtime, sandbox + the read-only library exception; what is inside it:
`raw/s0b-package-dmg.txt`). Second Mac: macOS 27 (exact build not reported), a Mac that had never seen the
project or its certificate, per the checklist in `docs/specs/M1-engine-spike.md`.

| Checklist step | Answer |
|---|---|
| 5. After Open Anyway: is there a Livepaper entry, does the colour show on the desktop, and on the lock screen? | **yes**, on both ("Colour shows on lock screen and home screen") |
| 6. Was `xattr -dr com.apple.quarantine` needed? | **no** (so step 6, and its `pluginkit` output, never came into play) |
| 7. Same after a reboot of the second Mac | not reported |

**Gate G1 passes: the render host is the extension** (`docs/adr/0001`). A quarantined, non-notarized,
self-signed download runs its wallpaper extension after Open Anyway alone.

Still worth a line when convenient: the second Mac's exact macOS build, and step 7.
