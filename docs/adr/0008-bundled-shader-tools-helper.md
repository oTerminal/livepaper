# Scene shaders are translated by bundled glslang and SPIRV-Cross helpers

At import, a scene's shaders are translated to Metal (record 0007): glslang preprocesses the items' GLSL and compiles it to SPIR-V, and SPIRV-Cross turns the SPIR-V into MSL. Spike S9 ran Homebrew's copies of both. The product ships its own: the two command-line tools, built from pinned source in CI by `Helpers/shader-tools/build.sh`, bundled next to the app's executable, and run by the importer as separate processes with a time limit.

A helper reuses the ffmpeg helper's machinery (record 0006): a build script with pinned sha256s, a CI artefact that carries the source and the licence texts, and a build step that bundles and signs the binaries. It also keeps untrusted input away from the app. The shaders come from Workshop items, and glslang and SPIRV-Cross are large C++ parsers, so a crash or a hang ends one helper process, never the app. No C++ goes into the Swift package, and the wallpaper extension never links or runs either tool: it only compiles the MSL that import wrote.

Unlike ffmpeg's, these licences do not call for a separate process. glslang is mostly BSD-3-Clause, and its Bison-generated parser is GPL 3 with the Bison exception, which allows it in a larger work under any terms. SPIRV-Cross is Apache-2.0. Their notices ship with the binaries (`NOTICE`, `Helpers/shader-tools/licenses/`).

## Considered options

- **Link glslang and SPIRV-Cross into the app through their C APIs** (`glslang_c_interface.h`, `spirv_cross_c.h`). No process per shader and no files between the steps, but two C++ code bases go into the Swift package's build, and a parser that crashes on a hostile shader takes the app down with it.
- **The user's own tools, if installed** (what S9 did, with Homebrew's). Nothing to build, but scene import would fail for most people with an instruction to install something.
