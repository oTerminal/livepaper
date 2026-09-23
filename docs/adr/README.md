# Decision records

One file per decision that is hard to reverse, surprising without context, and the result of a real trade-off. A record can be a single paragraph: what the situation was, what was decided, and why.

A record that is not settled yet, or that a later record replaced, says so in a bold **Status** line under its title; a record without one is decided.

Numbers 0001 to 0004 are the outcomes of the M1 engine spike (`docs/specs/M1-engine-spike.md`). The evidence behind them is in `Spikes/results/`.

| Number | Decides |
|---|---|
| [0001](0001-render-host-is-the-private-wallpaper-extension.md) | Render host: private wallpaper extension, or desktop-level window. *Gate G1 passed* |
| [0002](0002-library-in-application-support-with-a-read-only-exception.md) | Where the library lives and how the app and the extension talk |
| [0003](0003-the-user-selects-livepaper-once-and-quit-holds-a-still.md) | How the live wallpaper gets selected (by the app, through the wallpaper store, once), and what stopping does: the system wallpaper stays "Livepaper" and the extension holds a still |
| [0004](0004-self-signed-certificate-signed-inside-out.md) | Signing without a paid Apple Developer account |
| [0005](0005-wallpaper-engine-video-items-only.md) | Which Wallpaper Engine items are imported: video items only. *Superseded by 0007* |
| [0006](0006-bundled-lgpl-ffmpeg-helper.md) | Converting the formats AVFoundation cannot open, with a bundled LGPL ffmpeg helper |
| [0007](0007-wallpaper-engine-scenes-drawn-live.md) | Wallpaper Engine scenes drawn live in the extension, a GIF scene imported as video; web and application items still refused |
