# Reaper Tools

**Jeff scripts:** 44 of your Lua scripts are now individually installable in ReaPack under **Reaper Tools → Jeff**. Three additional scripts are archived pending repair. [Installation, requirements and preserving existing shortcuts](docs/JEFF-SCRIPTS.md).

## Wwise Relay — v0.3.4 Windows test build

A small REAPER panel that follows completed renders, automatically finds and replaces **existing Wwise SFX audio by sound name**, converts it using your chosen platform's existing settings, and shows a confirmation. **Show in Wwise** selects the sound's parent container.

**[Download Wwise Relay.lua](Wwise%20Relay.lua)** — open the file, then use GitHub's **Download raw file** button. The entire tool is in this one Lua file; you don't need the `src` folder on your PC.

**[Download the ZIP with instructions](Wwise-Relay.zip)** · **[Windows check guide](docs/WINDOWS-CHECKS.md)**

This repair was tested against real Wwise 2024.1.1 on Mac, including converted audio readback in a 20,000-Sound test project. Automated Windows tests cover the background helper and file handling. Native Windows REAPER/NVK rendering, your million-asset project and in-game playback still need your local check. No connection to that machine is needed. [Validation details](docs/LOCAL-VALIDATION.md).

### ReaPack

Import this URL using **Extensions → ReaPack → Import repositories**, then browse packages and install **Wwise Relay**:

```
https://raw.githubusercontent.com/soundguyjeff/Reaper-Tools/main/index.xml
```

[ReaPack installation and update guide](docs/REAPACK.md). The repository and downloads are public; no GitHub sign-in is needed.

### v0.3.4 — automatic checkout and startup arming

Relay asks Wwise to check out only the matched existing WAV when it is read-only. Configure your source-control provider in Wwise first. A failed checkout, a file still read-only, or a changed original pauses the update without replacing audio. Relay never clears the read-only attribute itself.

Update after render now arms automatically after connecting to the saved project and validating the platform. The existing render report is baselined, never replayed. A manual pause, error, or lost connection still requires explicit re-enabling within that session. Initial setup still requires choosing Use this project.

### v0.3.3 — linked project folders

Directory junctions and directory symbolic links such as `C:\Phobos` now resolve to their real local file paths. Relay pins the resolved render and original locations, checks them again before replacement, and rejects two paths that resolve to the same WAV. Links on individual files and network targets remain unsupported. The existing-object, WAV validation, read-only, conflict and no-backup checks remain in place.

Published through ReaPack after passing the [Windows validation run](https://github.com/soundguyjeff/Reaper-Tools/actions/runs/36056849578): all 37 Windows file checks, including real junction replacement and retarget rejection, plus Lua and asynchronous bridge tests. End-to-end testing with your Windows Wwise/NVK session remains.

### v0.3.2 — targeted matching and verified conversion

Relay asks Wwise for the exact Sound name and the owners of its particular original WAV. It no longer downloads the entire Sound/source catalog after each render. Matching queries have a one-minute limit while REAPER remains responsive. Wwise still evaluates those queries internally; million-asset performance has not been measured.

After replacing the WAV, Relay refreshes **only the existing AudioFileSource**, using its GUID and its own existing original file/subfolder. It never supplies a new Sound path or object type. This constrained refresh uses Wwise's existing-source import mechanism; general imports and creation remain unavailable. It checks the project, active source and exclusive ownership again, and requires Wwise to return that same source and file.

A rapid re-render may take up to two extra seconds to give the WAV a distinct timestamp. Changed sample data must produce a refreshed Wwise content identity before conversion. The converted WEM must contain that same identity, and the original must still contain the replacement bytes. This accepts valid older cached conversions when reverting to an earlier sound while rejecting stale audio. Metadata-only changes and identical renders are supported.

Timeouts identify the operation that failed. Diagnostic files are `Data/WwiseRelay/last-operation.txt` and `last-error.txt`. Hidden originals and cache files are supported.

### v0.3.1 — automatic Wwise connection

Open Relay and it connects in the background automatically. If Wwise is unavailable, the panel shows **Waiting for Wwise** and retries after 2, 4, 8, 16, then 30 seconds between attempts. It checks the connection while idle and verifies the saved project before accepting it. **Retry now** is available in Setup; changing the WAAPI port also starts a fresh attempt.

Connecting does not enable audio updates. First-time setup still needs **Use this project** and a conversion platform. Existing settings are kept. A detected connection loss or wrong project pauses enabled updates; after reconnecting, re-enable them when ready. Failed or uncertain audio updates are not replayed automatically. **Stop waiting** pauses automatic connection attempts until **Resume auto-connect** is clicked in Setup.

### v0.3.0 — keep REAPER responsive

Connecting to Wwise, all WAAPI requests, WAV inspection/hashing/replacement and conversion checks now run in a separate background PowerShell helper. Relay no longer calls ReaWwise's synchronous Lua connection/call functions. The panel resumes work in short steps, shows the current stage and has a **Stop waiting** button. Connection/simple reads time out after 15 seconds; filtered project searches get one minute and conversion gets two minutes. A helper that fails to start produces an error after 20 seconds without holding REAPER's interface.

Stopping or timing out does not undo a completed replacement or cancel a conversion already accepted by Wwise. Updates pause, and the message tells you to check Wwise before retrying. Pending replacement work checks the stop flag, request deadline and REAPER heartbeat before committing. The last helper operation is recorded locally in `Data/WwiseRelay/last-operation.txt` for diagnosis.

**Windows Script Host (`wscript.exe`, JScript) and Windows PowerShell 5.1 must be available.** The GUI script host starts the helper hidden without waiting in REAPER. If either is blocked, Relay reports it; it does not change system policy. ReaWwise can remain installed for NVK and your other tools, but Relay no longer requires or uses its shared connection.

Dropbox/Windows Cloud Files markers remain supported, while links on individual files and unknown tags remain blocked; directory links now resolve to local targets. Keep working audio available offline. Automated tests use a local WAMP test peer with deliberately stalled connections and synthetic files. Real Wwise conversion was also tested locally; native Windows/NVK verification is still required.

### Automatic matching

No manual audio links are needed. `Explosion_01.wav` automatically targets the existing Wwise Sound named `Explosion_01`. Choose the Wwise project and conversion platform once, enable updates, and render. This version also includes the v0.1.1 startup fix for REAPER 7.78 Win64.

Close Relay, synchronize ReaPack, then run it again. Existing project/platform preferences are kept. Old manual audio links are no longer used, and the Audio links tab has been removed.

### Install once

1. Have **REAPER 7**, **Wwise 2024.1.1**, **[ReaImGui 0.9.3 or newer](https://github.com/cfillion/reaimgui)** installed. ReaImGui is available through ReaPack. On a closed PC, transfer/install their Windows packages through your normal approved process. They are not included in this download.
2. Copy `Wwise Relay.lua` into your REAPER Scripts folder.
3. Open **Actions → Show action list → New action → Load ReaScript**, select the Lua file, and run it. You can give it a toolbar button.
4. Enable **Wwise Authoring API (WAAPI)** in Wwise's preferences. Relay connects locally to `127.0.0.1`, normally port `8080`.
5. Open Relay and wait for **Connected**. On first use, choose **Use this project** in **Setup**, then select the conversion platform used by your remote game connection.

The tool uses Windows Script Host for hidden startup and Windows PowerShell 5.1 for local WAAPI communication and file operations. It does not change PowerShell policy, require administrator rights, contact the internet, or use the game engine. If your organization's policy blocks PowerShell, Relay will stop with a message; do not relax the policy for this tool.

### How filenames find their sounds

Relay removes the final `.wav` extension and looks for that complete **Sound object name** in the pinned Wwise project. ASCII letter case is ignored; punctuation, spaces and version suffixes are kept. Non-ASCII characters must match exactly. There is no fuzzy matching or matching by container name.

- One matching Sound: use its active SFX file source on your chosen platform and replace the original file Wwise already references. The original WAV's own filename can differ from the Sound name.
- No matching Sound, or more than one Sound with that name: skip the WAV and show why. No new object or audio is imported.
- Shared original, localized voice, or no active file source: skip it.
- Two outputs in the same detected batch targeting the same sound/original: skip both rather than let processing order choose a winner.

Each render gets a fresh match. Renaming a render does not require setting up a link, provided the new filename matches a unique existing Sound. **Show file results** displays the matched Wwise object path. Nothing needs to be selected in Wwise.

### During work

Turn on **Update after render**, then render through NVK as usual. Leave Relay running. After a completed output is stable, Relay finds and verifies its matching sound, replaces the original, refreshes that existing source, requests conversion, and verifies the converted file. The compact panel starts at 440 × 300 and can be resized/docked using ReaImGui's normal window controls.

**Wwise audio updated** means the replacement's bytes were verified, the existing source was refreshed, Wwise returned no conversion warnings/errors, and the converted WEM's embedded content identity matches the refreshed source. **Show in Wwise** selects the updated parent container; if several were updated, choose one from the list. Your existing **Connect to Remote Platform** workflow remains in Wwise. Relay does not claim it has verified what played in the game.

An unmatched or ambiguous render is skipped. A failure pauses further replacements and lists any files that were not processed. Fix the cause and use **Retry skipped / failed files**, or re-enable and render again. If conversion fails after replacement, the new original remains in place. There is no rollback: **no previous-WAV backup is created**, as requested.

### Scope and limits

- No new audio, object creation/deletion, project saves, SoundBank generation, conversion-setting changes or source-control checkout. The only permitted import operation is a refresh of one existing source from its own existing original. The existing original and its converted cache are the intended changes.
- Exact project identity, unique sound name, source ID, parent, active source, original path and destination content are checked. Wrong projects, shared originals, read-only files, missing files and channel-count changes are rejected. The current original is hashed immediately before each replacement; if it changes during staging, replacement is rejected. Earlier edits are not remembered as conflicts between renders.
- Standard local RIFF WAV files only: PCM, float or extensible. Converted media must be a RIFF WEM with a Wwise content-hash chunk. No network paths, links on individual files, RF64/BW64, localized voice audio or semicolons in paths in this release. Render to a separate folder, not directly into Wwise Originals.
- Detection uses REAPER's latest completed `RENDER_STATS` report plus the listed files' timestamps/size. This is not a direct NVK callback. If NVK runs several native render groups before deferred scripts resume, only the final group's report may be visible. **Test your multi-group NVK workflow before relying on batch coverage.** Check the reported count against your outputs.
- A manual edit to a WAV still named in the last render report can also look like a new render. Pause Relay while externally editing those files. Merely opening Relay or enabling it establishes a baseline and does not replay old renders.
- Updates are sequential, not a batch transaction. Successful earlier files remain updated if a later one fails. Slow file operations and Wwise calls run outside REAPER; large responses are processed in short panel steps. Do not rename/reorganize the matched Wwise objects while a batch is updating.

Settings stay locally in REAPER's extension settings, keyed to the REAPER project’s master-track ID. The generated helper, hidden launcher and local session files live in REAPER's resource folder under `Data/WwiseRelay`. Temporary audio contains only the new rendered bytes and is removed after replacement; it is not a backup of the old WAV.

### Development

Edit `src/`, then run `python tools/build.py` to rebuild the root Lua deliverable. Run `python -m pip install lupa==2.8` and `python tests/run_tests.py` for Lua checks. On Windows, run `powershell -NoProfile -File tests/test_windows.ps1` for synthetic file checks. The optional `tests/test_live_wwise.py` additionally requires the isolated RelayTest fixture and an open Wwise 2024.1.1 instance. No tests connect to a game or production project.

References: [REAPER ReaScript API](https://www.reaper.fm/sdk/reascript/reascripthelp.html), [Audiokinetic WAMP client](https://github.com/audiokinetic/waapi-client), [Microsoft Windows Script Host](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wscript).
