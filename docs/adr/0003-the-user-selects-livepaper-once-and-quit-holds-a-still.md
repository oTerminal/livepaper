# The user selects Livepaper once; stopping holds a still instead of switching the system wallpaper back

Accepted by the product owner on 2026-09-21, from the four options under "Considered options". It replaces the roadmap's earlier "Quit restores the previous system wallpaper".

The roadmap wanted two things from macOS: that the app could make "Livepaper" the system wallpaper itself, and that Quit could put back whatever was there before, including an Aerial or a dynamic wallpaper. The M1 spike (S8, `Spikes/results/S8.md`, macOS 27.0) recorded what public API can do:

- **Nothing public selects an extension's wallpaper.** `NSWorkspace.setDesktopImageURL` takes an image file and that is all there is. The app can open System Settings on the Wallpaper pane; the click is the user's.
- **Nothing public can tell that Livepaper is selected, or name a previous Aerial.** While any extension-provided wallpaper is up, `desktopImageURL(for:)` returns the placeholder `/System/Library/CoreServices/DefaultDesktop.heic`. A previous wallpaper that is an image file (a still, or a dynamic `.heic`) does come back as its path.
- **`setDesktopImageURL` does take the desktop away from Livepaper, but apparently only on the Space that is active.** The call succeeded, the agent invalidated the extension's surfaces, and in the wallpaper store only the entries of one Space changed provider while the display-wide entry still named Livepaper. One display, and switching Spaces afterwards was not tried, so "the other Spaces keep Livepaper" is read off the store, not seen.
- **Swapping the wallpaper store file and restarting WallpaperAgent restored the earlier wallpaper in both cases tried** (back to Livepaper, back to an Aerial), within seconds. It is an undocumented file, it needs the agent restarted (which redraws every desktop; how that looks was not observed), and writing the whole file back discards whatever the user changed in between.

Put together: if Quit switched the system wallpaper back through public API, the next launch could not switch it to Livepaper again, and the user would be sent to System Settings every time. So:

- **Selecting.** Onboarding opens the Wallpaper pane and asks the user to choose "Livepaper". The app knows it happened when the extension's heartbeat reports a desktop surface, since no public API will say so. That is done once; re-signing, moving and updating the app all kept the selection in the spike.
- **Stopping (Pause all, Quit).** The system wallpaper stays "Livepaper". The app writes a stopped render state; the extension shows the current wallpaper's poster as a still and releases its decoders. Starting again is instant and needs nobody's help.
- **Leaving.** "Stop using Livepaper as wallpaper" in Settings, and the uninstall instructions, open the Wallpaper pane for the user to pick something else. If the wallpaper before Livepaper was an image file, the app offers to put it back with `setDesktopImageURL` and says that this covers the current Space.
- The store-file swap is not used by the product. `Spikes/results/S8.md` documents it for diagnostics.

These changed with it: the roadmap's Quit row ("Quit stops the live wallpaper and restores the previous system wallpaper") and its Risks row about restoring Aerials; the comment on `RenderHost.deactivate()` ("restores the previous system wallpaper"); and `CONTEXT.md`'s **Previous wallpaper**, which becomes something the app can offer to put back when it is an image file, not something it restores on every stop.

For comparison, Wallper 1.11.2 (looked at on 2026-09-21, bundle contents only) ships no wallpaper extension: it draws in a desktop-level window and sets a frame of the video as the system wallpaper through `setDesktopImageURL`, which is why it needs nobody's click and why quitting it leaves a freeze frame. A still after Quit is therefore what users of this kind of app already see; the extension host adds the lock screen, which a window cannot reach.

The extension must therefore be able to show something sensible with no app running: it reads the last render state on its own, and falls back to the poster when the state says stopped or is missing.

## Considered options

- **Quit restores through public API.** Partial (active Space only, never an Aerial) and it costs a trip to System Settings on every launch.
- **Quit restores by swapping the store file.** Complete, but built on an undocumented format that any update can change, with a visible agent restart, and it can silently undo the user's own wallpaper changes.
- **Stay selected, and show a copy of the previous wallpaper's image while stopped.** Looks like switching back on every Space and costs nothing at launch, but cannot work for an Aerial or a time-of-day wallpaper, and a desktop that looks like the old wallpaper while System Settings says "Livepaper" is its own confusion. Offered to the product owner, who chose the still.
- **Drive System Settings through accessibility to make the click.** Works (the spike did it to get going) but needs the Accessibility permission, and the roadmap rules out permission-gated API.
