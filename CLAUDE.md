# Livepaper

Product and engineering decisions live in `docs/roadmap.md`, milestone specs in `docs/specs/`, decision records in `docs/adr/`, vocabulary in `CONTEXT.md`, and the value behind every design-system token and component in `Packages/DesignSystem/DECISIONS.md`. Read the relevant ones before proposing anything; they are not re-litigated in a PR.

## Pull requests

One PR per milestone, its body written for a reviewer who will not run the branch. Every PR body shows the work on screen:

- A **screenshot** of every screen, component or state the PR adds or changes, cropped to the part that matters.
- A **video** of every motion or interaction it adds or changes: a GIF inline, its MP4 linked beside it. Record at the Gallery's 0.1x where the motion is quick.
- A **before and after** pair when the PR fixes something visible.

`Tools/pr-media/shot.sh` captures the Gallery window, `record.sh` records it and writes the MP4 and GIF, and `publish.sh <pr> <files>` puts them on the orphan `pr-media` branch and prints the Markdown to paste. Media never goes into master's history. Captures show the user's screen: capture the window, not the display, and look before publishing.

## Checks

`make gen build test lint` must be green before a push; CI runs the same on macos-26 / Xcode 26, which is older than the local toolchain, so keep to Swift features that Xcode 26 has.
