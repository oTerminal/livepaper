# Releases are signed with our own self-signed certificate, inside-out, without the hardened runtime

There is no paid Apple Developer account, so nothing is notarized and Gatekeeper will always ask the user to approve the first launch. What the signature still has to do is keep the app's identity the same from one build to the next, so that macOS treats an update as the same app.

Release builds are signed with one long-lived self-signed code-signing certificate. The extension is signed first, with its own entitlements file (`com.apple.security.app-sandbox` plus the library exception from record 0002); then the app. Never `codesign --deep`. No hardened runtime. Local and CI builds stay ad-hoc.

What the M1 spike observed on macOS 27.0 (`Spikes/results/S0.md`, `S0c.md`):

- **The wallpaper extension loads under every combination tried**: ad-hoc or self-signed, from DerivedData or /Applications, hardened runtime on or off, and after a rebuild. amfid logs `-423 "adhoc signed or signed by an unknown certificate chain"` for both kinds of signature and it is not fatal. The one fatal thing the spike ran into is a missing sandbox entitlement: ExtensionKit then refused the extension at discovery ("not entitled to run in the App Sandbox"; seen once, on the raw Xcode product).
- **A self-signed certificate gives a stable identity; ad-hoc does not.** Two builds with a source change between them had the same designated requirement, `identifier "app.livepaper.spike" and certificate leaf = H"6741…3de7"`. The ad-hoc builds' requirement is `cdhash H"…"`, different for every build.
- `codesign` signs with a certificate that nothing trusts; it only has to be in a keychain on the search list. The spike keeps it in its own keychain.
- The hardened runtime changed nothing for loading, so it stays off: it buys nothing without notarization, and it would put library validation between Sparkle and its helpers.
- `SMAppService.mainApp` reported `enabled` after the app was replaced by a second build, for both kinds of signature. Whether the login item then really launches the new build, with one row in Login Items, takes a logout and is on the run sheet; this record is revisited if the self-signed build fails that.

Consequences:

- Losing the certificate's private key changes the app's identity for every user. It is backed up outside the repo and lives in CI as a secret (M9).
- The second-Mac test (S0b) decides whether any of this reaches users. Until it is run this record describes what works on the development Mac.
- `hdiutil create` is deprecated on macOS 27 in favour of `diskutil image create`. The spike's DMG script still produced a valid image with it (`Spikes/results/raw/s0b-package-dmg.txt`); M9 should move.

## Considered options

- **Ad-hoc everywhere.** Loads just as well, but every update is a different app to macOS: the designated requirement is the code hash.
- **A free Apple Development certificate.** Expires, is tied to one person's Apple ID and registered devices, and still is not notarized.
- **Hardened runtime on.** Works, no benefit without notarization, a cost for Sparkle.
