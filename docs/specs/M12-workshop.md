# M12: the Wallpaper Engine Workshop

A user who owns Wallpaper Engine on Steam signs in once inside Livepaper, browses Wallpaper Engine's Workshop, and gets items straight into the library. Built beside the port of S9's renderer (M11), at the product owner's request. See record 0009 (items downloaded with the user's own Steam login through Valve's steamcmd), 0007 (scenes, GIF scenes, web and application items refused), 0002 (the library, and the app outside the sandbox), `CONTEXT.md` and `DECISIONS.md`.

## Rules

- Code goes in a new nonisolated target `LivepaperWorkshop` in `LivepaperKit`, which depends on `LivepaperImport` for discovery's results and words, and in `App/Workshop/`. The design system gains a component for each new control, each with a Gallery page and a `DECISIONS.md` entry. Shared files change only by small additions (`Package.swift`, `project.yml`, the app's scenes, the library window's toolbar, the popover's footer, Settings), so the branch merges beside M11's port.
- Pure where it can be, and test-first with Swift Testing: links, steamcmd's lines, the conversation with its console, the download list, the words and the item page are table-tested. The pty driver, the installer and the jobs run against a fake steamcmd script (`Fixtures/fake-steamcmd`) and archives the tests make. No test touches Steam, and none reads a Workshop file: they are other people's work and never go into the public repository.
- The password and a Steam Guard code are never an argument, never on disk, never in the log, and held in memory for the one sign-in (record 0009). Only the account name is kept.
- A download never types a password. One that meets a password prompt stops and asks the user to sign in.
- steamcmd runs one job at a time, and never runs unless it carries Valve's signature.
- Vocabulary is `CONTEXT.md`'s: Workshop, Workshop item, Get, Steam account, saved login, and the import's words for what happens next. A downloaded folder is imported as a dropped one is; nothing about import changes.
- Nothing on screen is a stand-in. The words are the house voice (`ImportWords`' style: whole sentences, what happened and what helps).
- CI builds with Xcode 26 on macos-26, which is older than the local toolchain, so keep to what Xcode 26 has (CLAUDE.md).

## What earlier milestones settled

- **Import** (M4, M6, M11). `discoverSources` reads a Wallpaper Engine folder by its `project.json`: a video item gives its video, a scene its package, a GIF scene becomes video, a web or application item is skipped with `runsCode` and `skipWords`. The import list runs one import at a time, and a file already in the library is a duplicate before any conversion. `AppModel.importItems(at:)` is how a drop or the Open panel starts one.
- **Screens** (M6). The library window's toolbar has Import; the popover's footer has symbol buttons into the library and Settings; Settings' General pane is a grouped form. Every screen composes `DECISIONS.md`'s components.

## steamcmd

| Part | Does |
|---|---|
| `SteamCmdTool` | Lives in `~/Library/Application Support/Livepaper/Steam/steamcmd/`. `install` fetches Valve's archive over https, unpacks it with `tar` beside the folder, checks the executable against `CodeSignature.valve` (Valve's Developer ID, team MXGJJ98X76, under Apple's root), then renames it into place; nothing is left behind on a failure, and a steamcmd already there is replaced only by one that passed. `check` repeats the signature check before every run and reads the executable's architectures (`machOArchitectures`), since the archive's steamcmd is Intel only and needs Rosetta (`rosettaProblem`) |
| `SteamCmd` | Runs one `SteamJob` (`signIn`, `download`, `signOut`, `update`) through `PseudoTerminalProcess`: a pty with echo off, `posix_spawn` in a session of its own with no other descriptor, the environment steamcmd.sh sets and nothing else. Only `+@sSteamCmdForcePlatformType windows` is an argument. Exit 42 (steamcmd.sh's restart after an update) starts it again. A time limit per job (10 min for a sign-in, 60 for a download), and 20 s to go once it has answered. Cancelling stops its process group |
| `SteamTranscript`, `readSteamLine` | steamcmd's bytes into lines, including the open line a prompt waits on (`Steam>`, `password:`, the Steam Guard prompts, `Waiting for confirmation...`), and each line into a `SteamLine` |
| `SteamConversation` | Pure: what to type and when, for one job. Commands only at `Steam>`, since steamcmd drops what is typed ahead. `typePassword` and `askForCode` stand for the secrets, which the reducer never holds |
| `WorkshopError`, `workshopFailureWords` | Steam's results read into what Livepaper can say something useful about, the rest in Steam's words; each with its words and whether Retry or a sign-in would help |

## Getting items

| Part | Does |
|---|---|
| `WorkshopLink` | An item's number from its page's link, Steam's own `steam://url/CommunityFilePage/<id>`, or pasted text; the Workshop's front page; which pages stay in the window (Steam Community over https), which go to the browser, and which are refused (scripts, files, data, `steam://`) |
| `WorkshopItemPage` | From an item page's HTML: its app, its title, its "Type" tag and its preview picture. A page of another app's item is refused (`notWallpaperEngine`); a Web or Application item is refused with discovery's own `skipWords` before anything is downloaded |
| `WorkshopDownloads` | Pure: the items asked for, one downloaded at a time, each handed to the import once discovery has read its folder (`DiscoveredItem`). No saved login holds every item until the user signs in. Its rows are `ImportProgressRow`s, with `workshopStageWords` as the detail |

## The app

| Screen | Composes, and what it does |
|---|---|
| Workshop window | A `Window` of its own (`AppWindows.workshopID`), opened from the library window's toolbar, File > Wallpaper Engine Workshop (⇧⌘O) and the popover's footer; the Dock icon follows it as it follows the library window. A `WKWebView` on Steam's Workshop pages (`WorkshopBrowser`), Back, Forward and Workshop Home, `WorkshopGetButton` for the item whose page is open, and a Steam account menu. The rows being got and imported under the page |
| Sign-in sheet | `SteamSignInForm` on the window it was asked from (the Workshop window or Settings). Setting steamcmd up is its first step when it is not there yet |
| Library window | A Workshop link or item number pasted (Edit > Paste) or dropped is got; pasted files are imported. The Workshop's rows sit above the import list |
| Settings | A Wallpaper Engine Workshop section in General: the Steam account, Sign In, or Sign Out behind a confirmation (steamcmd's `logout`) |
| Fakes run | `WorkshopServices.fakes()`: steamcmd's steps on the clock, no network. A password of "code" asks for a code, "approve" waits for the app, "wrong" is refused; an even item number downloads a made-up video item, an odd one is refused as an account without Wallpaper Engine is |

## Seams for test-first work

| Seam | Tested as |
|---|---|
| `WorkshopLink` | Item pages, their older path, http, www, capitals, Steam's own link; lookalike hosts, a name and password, a port, the front page, change notes, no id, zero, too large, two ids, a file; pasted text; which pages stay |
| `readSteamLine`, `SteamTranscript` | Lines steamcmd printed on this Mac (the account, Steam ID and home folder replaced), lines from its `console_log.txt`, Steam Guard's prompts and results; colours and carriage returns; prompts on an open line, each read once; a line or a character split across reads; a warning on the same line as a result; the last lines kept |
| `SteamConversation` | Each job's order of commands; a download or sign-out never answering a prompt; the password once; codes, again when refused; approval said once; each refusal's reading; exit 42 and any other exit; an account name that would be two commands |
| `SteamCmd` on the fake | Download with a saved login, then discovery on the folder; no saved login; an item Steam lacks; sign-in with the password typed and never echoed or passed as an argument; a wrong password; an emailed code; a wrong app code; approval; a code not given; sign-out; the first run's update and restart; a crash; silence past the time limit; cancel; a program that will not start; secrets with line breaks refused and printed as dots |
| `SteamCmdTool` | Mach-O headers, thin and universal; Rosetta's verdict; a signature from the signer asked for, from another, from nobody, altered, missing; install from an archive of a signed and of an unsigned `steamcmd`, a broken archive, a failed fetch, each leaving nothing behind |
| `WorkshopItemPage` | A scene's page; entities in a title; the refusals by type and app; a page that is not an item's; a preview not on https |
| `WorkshopDownloads` | One at a time in order; the row following steamcmd; discovery then the handover and the next; discovery passing over, or finding nothing; a refusal from the page; a failure and the next; the hold for sign-in and its release; asking twice; retry in place; retry held for sign-in; cancel running, waiting and failed; news of a row no longer running; the words |
| `workshopFailureWords` | Every error's words and what helps; none ends in a full stop |

## Checks

| # | Check | Pass when |
|---|---|---|
| 1 | `make gen build test lint` | Green, with no warnings |
| 2 | Set steamcmd up from Valve through `SteamCmdTool.install` into a scratch folder, then its first run (`SteamCmd.run(.update)`) in a home folder of its own | Valve's signature before and after the update; Rosetta found; the updated steamcmd has Apple silicon code |
| 3 | Download 3289988463 with the user's saved login through `SteamCmd.run(.download)`, compare it with the user's copy in `we-samples/`, and run `discoverSources` on the folder | `Success.` read; every file byte for byte the same; one scene candidate, "Lonely Cat" |
| 4 | The same for a small item not yet in Steam's folder | A fresh download, byte for byte the same, read by discovery |
| 5 | An anonymous login for 431960, in a home folder of its own | Refused (`Failure`), which Livepaper reads as `notOwned` |
| 6 | Every state of `SteamSignInForm`, `WorkshopGetButton` and the download rows in the Gallery, captured by window and looked at | Nothing cut off or misaligned |
| 7 | After the merge, by the user: the sign-in sheet against real Steam | See "What the user tries" below |
| 8 | After the merge, by the user: the Workshop window, Get, a pasted link, a dropped link, sign-out | See below |

## Done when

- The seam tests pass with `swift test --package-path Packages/LivepaperKit`, locally and in CI, and `make gen build test lint` is green.
- Checks 1 to 6 pass on this Mac, with their evidence here; checks 7 and 8 are listed for the user, who alone can sign in.
- Record 0009, the roadmap's Import row, `CONTEXT.md` and `DECISIONS.md` say what was built.

## Out of scope

Subscribing to items on Steam, updating downloaded items when their author changes them, collections, a Workshop search of Livepaper's own, Web API keys, and any account but the user's. Removing a downloaded item from Steam's folder. Items of any app but Wallpaper Engine. Web and application items, as ever (record 0007).

## As built

What M12 decided or found on the way. Names are quoted from the code.

### steamcmd, as seen on this Mac (macOS 27.0, 2026-09-23)

- The console is driven, not the command line: the account name is typed after `login` at `Steam>`, as are the password and codes at their prompts. steamcmd drops what is typed before its first `Steam>` (seen: four commands typed ahead were lost), so `SteamConversation` types only at a prompt.
- Echo is switched off on the pty before steamcmd starts, so nothing typed comes back; a prompt is read from the open line and dropped, and steamcmd's next words then follow it on the same line. `SteamCmdTests` checks that no line holds the password or the `login` command.
- steamcmd's warnings share the terminal and land on the same line as its results (seen: `Downloading item 3775394622 ...PosixFileOpen: RESOLVE_BENEATH unsupported, falling back to plain open()`), so a download's result is matched at the end of a line.
- The archive's steamcmd (4,638,880 bytes, Intel only, Valve's Developer ID, signed 2 April 2020) fetched 15,667 KB of itself on its first run, said "Update complete, launching...", and went on as a universal build, still Valve's. Whether it relaunched itself or exited 42 for the driver to start it again, the job carried on; both are handled. Setting up took 18.7 s, the fetch of the archive included.
- An account's saved login is found by its name, so `WorkshopServices` keeps the name in the defaults (`WorkshopAccount`). A download that meets `password:` is stopped at once with `signInNeeded` and nothing typed.
- A downloaded item stays where steamcmd put it, in Steam's folder, and is imported from there as a dropped folder would be.
- Where Get differs from Wallpaper Engine's own Workshop: it downloads once (`workshop_download_item`) and never subscribes, so the item is not among the account's subscriptions on Steam and is not updated when its author changes it; it gets the Windows copy, as Wallpaper Engine would; and it is one item at a time, never a collection. Once imported, a scene is drawn with the differences M11-wallpaper-engine-scenes.md lists ("As built").

### The app

- `WorkshopModel` (`App/Workshop/`) runs steamcmd one job at a time (`takeSteam`), sets it up on first use from the sign-in or the first Get, and keeps the Get button's done for the session (`handedOver`). A sign-in's password goes from the sheet's field into one `SteamSecret` in one task; the sheet's fields go with the sheet. Quit stops steamcmd (`stopAll`), which runs in a session of its own.
- The Workshop window reads an item page's HTML after it loads (`evaluateJavaScript("document.documentElement.outerHTML")`) and nothing else; nothing is injected. The web view's website data store is the default one, so a sign-in to Steam Community in the page itself lasts, as in a browser; Livepaper never reads it.
- The row's poster is the page's preview picture, fetched to a temporary file.
- The Workshop window, the sheet in the app, Settings' section and the popover's button compile, with previews, but were not seen on screen: the app was not launched on this Mac while M11's port owned the installed build and the desktop. The sheet's content and the Get button were seen in the Gallery. (They were seen on 2026-09-24, with the installed build: "On screen", below.)

### Log lines

`app.livepaper.Livepaper`, category `workshop` (`WorkshopLog`), `.notice` unless marked. No line holds a password or a code, and none names the account:

- `workshop: getting item <id>`
- `workshop: setting up steamcmd from https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz`, then `workshop: steamcmd set up, Valve's signature checked`
- `workshop: item <id> downloaded, <bytes> bytes`, then `workshop: item <id> handed to the import` or `workshop: item <id> refused: <problem>`
- `workshop: item <id> not got: <error>` (`.error`)
- `workshop: signing in to Steam`, `workshop: signed in to Steam; steamcmd saved its login`, `workshop: sign-in failed: <error>` (`.error`), `workshop: sign-in cancelled`
- `workshop: signed out of Steam; steamcmd's saved login revoked`, `workshop: sign-out failed: <error>` (`.error`)
- `steamcmd: <line>`, every line steamcmd prints, at `.debug` and private, since they name the account

### The checks, run on this Mac on 2026-09-23

Through a scratch harness linking `LivepaperWorkshop` and `LivepaperImport`, with the saved login the user's steamcmd already had. No password was typed and `logout` was never run against the user's account.

| # | Result |
|---|---|
| 1 | Pass: 90 `LivepaperWorkshop` tests; the whole package, the design system, the three schemes and lint green, no warnings |
| 2 | Pass: installed from Valve, signature `true` before and after, "check passed (Rosetta installed: true)", then `updated`; architectures after the update Apple silicon and Intel |
| 3 | Pass: `Logging in using cached credentials.` … `Success. Downloaded item 3289988463 to "…/workshop/content/431960/3289988463" (4404844 bytes)` in 4.4 s; `scene.pkg`, `project.json` and `preview.jpg` identical to `we-samples/3289988463`; discovery: one candidate, "Lonely Cat", a scene, with `preview.jpg`. The item was already in Steam's folder from the product owner's check earlier that day, so steamcmd checked it rather than fetched it; check 4 is the fresh fetch |
| 4 | Pass: 3775394622 (13,490,478 bytes), not in Steam's folder before, downloaded in 7.6 s; `scene.pkg`, `project.json` and `preview.gif` identical to `we-samples/3775394622`; discovery: one candidate, "Agamemnon", a scene |
| 5 | Pass: `ERROR! Download item 3289988463 failed (Failure).` |
| 6 | Pass, dark appearance, the window inactive: every step of the sheet and every state of the button and the rows. The code field's prompt was cut off at title size and was shortened to "Code" |

### On screen, with the installed build (2026-09-24)

The branch's final build, installed and running, driven by Accessibility presses with the pointer and the keyboard untouched. No password was typed, and neither a sign-in nor a sign-out ran.

- A Workshop link pasted into the library window (Edit > Paste): `workshop: getting item 3289988463`, `workshop: setting up steamcmd from …`, `workshop: steamcmd set up, Valve's signature checked` 14.6 s later, `workshop: item 3289988463 downloaded, 4404844 bytes` 4.7 s after that with the saved login, `workshop: item 3289988463 handed to the import`, then the import's `duplicate of wallpaper … "Lonely Cat"`. The row read "Starting Steam's download tool", "Updating Steam's download tool" up to 100 %, "Signing in to Steam", "Downloading from Steam", then the import's "Finished".
- The app set steamcmd up in `Livepaper/Steam/steamcmd/`, and steamcmd's `Frameworks -> MacOS/Frameworks` link landed in `Livepaper/Steam/`, not in the library's root. The `Livepaper/steamcmd/` an earlier build had set up, and the link it had left in the root, went to the Trash first.
- Seen: the Workshop window's toolbar (Get disabled on the Workshop's front page, "Go to an item's page to get it", and enabled on an item's page), Settings' section signed in, and, in the fakes run, the sign-in sheet on Settings, cancelled.

### Sign-out, and a saved login Steam refuses (2026-09-24)

After the merge the user signed out in Settings (`workshop: signed out of Steam; steamcmd's saved login revoked`, 09:19:23), then tried to sign in again twice: `workshop: sign-in failed: steamSaid("Access Denied")`, about 3 s after each start, before any password was asked for. steamcmd's own `logs/console_log.txt` (in `Livepaper/Steam/steamcmd/`) showed why:

- The sign-out ran as built: the saved login, `logout` ("Logging off current session... OK"), then `login` again, which said `Cached credentials not found.` and `password:`. Livepaper stopped steamcmd at that prompt, as the proof it wanted. steamcmd never reached `Unloading Steam API...`.
- Each sign-in after it began `Logging in using cached credentials.` and ended `ERROR (Access Denied)`. steamcmd forgets a login at `logout` but writes that down only when it quits, so the revoked login was still on disk, and it tried that instead of asking for the password.
- Checked by hand with the app's steamcmd, typing nothing secret: `login` gave `Access Denied` from the cached credentials; `logout`, then `quit`, exited 0; the next run's `login` said `Cached credentials not found.` and asked for the password.

Neither of the handoff's other leads was it: Steam said `Access Denied` to the cached login within 2 s, so no rate limit was met and no password line was ever typed over the pty.

So a `logout` is now always followed by `quit`, and the job goes on in a new run of steamcmd (`SteamConversation`'s `.restart`). A sign-out logs out, quits, and proves the login gone in the second run. A sign-in whose saved login Steam refuses (anything but no connection, a timeout or a rate limit) logs out of it, quits, and asks for the password in the second run; refused again, it ends with Steam's words. A download whose saved login Steam refuses asks the user to sign in (`signInNeeded`). The fake steamcmd now keeps a `logout` only when it quits, and can hold a revoked login; against it the old driver failed six tests, the user's case among them ("after signing out, signing in again asks for the password").

### What the user tries after the merge

With the merged build installed and running, on this Mac:

1. Popover > the globe (Wallpaper Engine Workshop): the Workshop window opens on Wallpaper Engine's Workshop and the Dock icon comes. The library window's toolbar button and File > Wallpaper Engine Workshop (⇧⌘O) open the same window. A link off Steam Community opens in the browser.
2. The person menu > Sign In to Steam…: the sheet first sets steamcmd up in `~/Library/Application Support/Livepaper/Steam/steamcmd/` (about 20 s; the check above ran in a scratch folder, so the app's own setup has not run), then asks for the account name and password. Then, as Steam asks, the code from the Steam Mobile app, the emailed code, or the approval in the app. The sheet closes signed in; Settings shows the account. Also try a wrong password once: the sheet says Steam did not accept it, and the fields keep what was typed.
3. Open a scene's page (Lonely Cat, 3289988463) and press Get: the row goes Starting, Signing in, Downloading, then the import's row, and a scene wallpaper appears in the library. Get on the same page again: the import says it is already in the library.
4. Open a video item's page and Get it; open a Web item's page: Get is disabled with the reason.
5. In the library window, paste `https://steamcommunity.com/sharedfiles/filedetails/?id=3775394622` (Edit > Paste), and drag an item's link from Safari onto the window: each is got.
6. Settings > Sign Out of Steam…: the account goes; a Get then asks to sign in. (This revokes steamcmd's saved login, so sign in again after.) Sign in again from Settings this time: the sheet opens on the Settings window.
7. Get a large item and cancel its row while it downloads; Get another and Quit Livepaper while it downloads. Each time `pgrep -fl steamcmd` finds nothing a few seconds later.
8. VoiceOver on the sign-in sheet and the Get button, which `DECISIONS.md` records as not yet walked.
9. `log show --last 30m --predicate 'subsystem == "app.livepaper.Livepaper" && category == "workshop"'` shows the lines above and no password.
