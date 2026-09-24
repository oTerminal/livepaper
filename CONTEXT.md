# Livepaper

A macOS app that plays a video the user provides, or draws a Wallpaper Engine scene, as their wallpaper, on the desktop and the lock screen.

## Language

### Library

**Wallpaper**:
A looping video, or a Wallpaper Engine scene drawn live, in the library that can be shown on a display.
_Avoid_: Video, clip, asset, item

**Library**:
The user's collection of wallpapers, stored and managed by the app.
_Avoid_: Collection, gallery, media

**Import**:
Bringing a file or a Wallpaper Engine item the user provides into the library as a wallpaper.
_Avoid_: Add, upload, ingest

**Source file**:
The file the user provided for an import. It stays where it was and is never modified.
_Avoid_: Original, input

**Optimised copy**:
The one video file the library keeps for a video wallpaper, prepared at import so it loops without a gap. A scene has none: the library keeps the scene's own files.
_Avoid_: Transcode, converted file, cache

**Poster**:
A still image of a wallpaper, shown wherever the wallpaper is not playing.
_Avoid_: Thumbnail, preview image, snapshot

**Wallpaper Engine video item**:
A Wallpaper Engine Workshop folder whose project is of type video. Its video is imported as any other source file is.
_Avoid_: WE wallpaper, workshop wallpaper

**Scene**:
A Wallpaper Engine scene item: a package of layers, effects and particles, drawn live by the extension. Web and application items, which run code of their own, are never imported.
_Avoid_: WE wallpaper, workshop wallpaper, 3D wallpaper

**GIF scene**:
A scene whose only content is one image layer with an animated sprite sheet. Imported as video, since its frames loop exactly.
_Avoid_: GIF template, animated scene

**Programs**:
A scene's shaders translated to Metal by the app, kept beside the scene's files (record 0008). Preparing a scene writes them, at import and again at launch when they are missing or from another translation; the extension only compiles them, and a scene without them holds its poster.
_Avoid_: Compiled shaders, shader cache

**Workshop**:
Wallpaper Engine's Workshop on Steam Community, where its items are published. Livepaper shows Steam's own pages in its Workshop window (record 0009).
_Avoid_: Store, marketplace, catalogue

**Workshop item**:
One entry in the Workshop, known by its number. Downloaded, it is a Wallpaper Engine folder: a video item, a scene or a GIF scene, which is imported as any such folder is, or a web or application item, which is not.
_Avoid_: Mod, asset, download

**Get**:
Downloading a Workshop item with the user's Steam account and handing its folder to the import. The Workshop window's primary action; a pasted or dropped Workshop link does the same.
_Avoid_: Subscribe, install, fetch

**Steam account**:
The user's own account on Steam, which must own Wallpaper Engine for its Workshop items to download. Livepaper keeps its name, never its password.
_Avoid_: Login, user, profile

**Saved login**:
What Steam's download tool (Valve's steamcmd) keeps after the user signs in, so that later downloads need no password. Signing out revokes it.
_Avoid_: Session, token, cached credentials

**Favourite**:
A wallpaper the user has marked to find again quickly.
_Avoid_: Starred, liked

### Showing wallpapers

**Display**:
A physical screen, recognised as the same screen after it is unplugged and plugged back in.
_Avoid_: Screen, monitor

**Assignment**:
The choice of which wallpaper, or which playlist, a display shows.
_Avoid_: Mapping, binding, selection

**Presentation**:
How a wallpaper is fitted to a display: fit mode, focal point, pan and zoom.
_Avoid_: Layout, scaling, crop settings

**Focal point**:
The part of a wallpaper that stays in view when it is cropped to fill a display.
_Avoid_: Anchor, centre

**Playlist**:
An ordered set of wallpapers that a display rotates through.
_Avoid_: Queue, album, shuffle set

**Rotation**:
A playlist moving a display on to its next wallpaper, on an interval, on wake or at login.
_Avoid_: Cycling, slideshow, shuffle

**Pause rule**:
A condition the user can switch on under which playback stops to save energy, such as the desktop being fully covered.
_Avoid_: Power setting, battery mode

**Live wallpaper**:
The state in which Livepaper, rather than a system wallpaper, is what the displays show.
_Avoid_: Active mode, running

**Selection**:
Livepaper being the system wallpaper: what the wallpaper store names for the desktop, made by onboarding's one edit of the store or by the user's click in System Settings, and ended only by leaving (record 0003). Not the library grid's selection, the one tile picked in the window.
_Avoid_: Activation, enabled, installed

**Previous wallpaper**:
The system wallpaper that was set before the user chose Livepaper. Stopping does not bring it back (record 0003); it is put back when the user leaves Livepaper.
_Avoid_: Original wallpaper, backup

### Rendering

**Render host**:
The part of the system that puts a playing wallpaper on screen.
_Avoid_: Renderer, backend, engine

**Surface**:
One place a display's wallpaper is drawn: a desktop Space, the lock screen, or the System Settings preview.
_Avoid_: Layer, window, view

**Metal slot**:
The layer in a surface's tree where a scene is drawn, made with the rest of the tree before the surface is hosted, and shown or hidden by an opacity change (record 0007).
_Avoid_: Scene layer, canvas, Metal view

**Loop seam**:
The moment a wallpaper's last frame is followed by its first. A visible flash or stall there is a defect.
_Avoid_: Loop point, wrap
