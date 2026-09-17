# Wallpaper Engine support stops at video items

Wallpaper Engine's Workshop is roughly 41% video items (a plain mp4 or webm beside a `project.json`), 54% scenes and 4% web pages. Livepaper imports video items and nothing else, permanently.

Scenes need a full reimplementation of Wallpaper Engine's renderer in Metal: a parser for its packed texture format, a translator for its GLSL dialect, particles, skeletal animation and a scripting runtime. Every free project that attempted it stalled, the complete ones are GPL (incompatible with this MIT codebase), and the shader headers scenes depend on are proprietary files that ship with Wallpaper Engine, not with the Workshop item. Web items would mean running untrusted JavaScript around the clock in a web view. Both would turn a small finished app into an open-ended renderer project.

Livepaper never downloads from Steam. Users drop a Workshop folder they already have.
