# Reaper Tools

## Wwise Relay — v0.2.2 Windows test build

A small REAPER panel that follows completed renders, automatically finds and replaces **existing Wwise SFX audio by sound name**, converts it using your chosen platform's existing settings, and shows a confirmation. **Show in Wwise** selects the sound's parent container.

**[Download Wwise Relay.lua](Wwise%20Relay.lua)** — open the file, then use GitHub's **Download raw file** button. The entire tool is in this one Lua file; you don't need the `src` folder on your PC.

**[Download the ZIP with instructions](Wwise-Relay.zip)** · **[Windows check guide](docs/WINDOWS-CHECKS.md)**

This is a first test build. Automated logic, simulated workflows and synthetic file tests do not establish live REAPER/NVK/Wwise compatibility. The remaining checks happen on your Windows machine. No connection to that machine is needed.

### ReaPack

Import this URL using **Extensions → ReaPack → Import repositories**, then browse packages and install **Wwise Relay**:

```
https://raw.githubusercontent.com/soundguyjeff/Reaper-Tools/main/index.xml
```

[ReaPack installation and update guide](docs/REAPACK.md). The repository and downloads are public; no GitHub sign-in is needed.

### v0.2.2 — quiet file checks and Windows startup fix

Replaces the repeating PowerShell launches with one background inspector created without a console window. Failed WAV checks now show the filename and actual error, then pause after an eight-second grace period for files still being written. The inspector stops when Relay is paused/closed and expires after being idle; it starts again when needed. It is read-only: audio replacement still runs through the existing verified replacement operation.

The v0.2.1 Windows bridge check exposed a startup hang caused by inherited process handles. v0.2.2 launches the inspector with Windows CreateProcessW, no inherited handles and CREATE_NO_WINDOW. This launcher requires PowerShell Add-Type; blocked compilation produces an error and pauses updates.

The recording of the v0.2.0 failure established the repeating console-window problem. It did not reveal the underlying WAV inspection error; the new file-error display makes that visible instead of leaving the panel silently waiting.

### Automatic matching

No manual audio links are needed. `Explosion_01.wav` automatically targets the existing Wwise Sound named `Explosion_01`. Choose the Wwise project and conversion platform once, enable updates, and render. This version also includes the v0.1.1 startup fix for REAPER 7.78 Win64.

Close Relay, synchronize ReaPack, then run it again. Existing project/platform preferences are kept. Old manual audio links are no longer used, and the Audio links tab has been removed.

### Install once

1. Have **REAPER 7**, **Wwise 2024.1.1**, **[ReaImGui 0.9.3 or newer](https://github.com/cfillion/reaimgui)** and **[Audiokinetic ReaWwise](https://github.com/audiokinetic/ReaWwise)** installed. ReaImGui and ReaWwise are REAPER extensions available through ReaPack. On a closed PC, transfer/install their Windows packages through your normal approved process. They are not included in this download.
2. Copy `Wwise Relay.lua` into your REAPER Scripts folder.
3. Open **Actions → Show action list → New action → Load ReaScript**, select the Lua file, and run it. You can give it a toolbar button.
4. Enable **Wwise Authoring API (WAAPI)** in Wwise's preferences. Relay connects locally to `127.0.0.1`, normally port `8080`.
5. In Relay's **Setup** tab: **Connect to Wwise → Use this project**, then select the conversion platform used by your remote game connection.

The tool uses Windows PowerShell 5.1 for file validation and replacement. It does not change PowerShell policy, require administrator rights, contact the internet, or use the game engine. If your organization's policy blocks PowerShell, Relay will stop with a message; do not relax the policy for this tool.

### How filenames find their sounds

Relay removes the final `.wav` extension and looks for that complete **Sound object name** in the pinned Wwise project. ASCII letter case is ignored; punctuation, spaces and version suffixes are kept. Non-ASCII characters must match exactly. There is no fuzzy matching or matching by container name.

- One matching Sound: use its active SFX file source on your chosen platform and replace the original file Wwise already references. The original WAV's own filename can differ from the Sound name.
- No matching Sound, or more than one Sound with that name: skip the WAV and show why. No new object or audio is imported.
- Shared original, localized voice, or no active file source: skip it.
- Two outputs in the same detected batch targeting the same sound/original: skip both rather than let processing order choose a winner.

Each render gets a fresh match. Renaming a render does not require setting up a link, provided the new filename matches a unique existing Sound. **Show file results** displays the matched Wwise object path. Nothing needs to be selected in Wwise.

### During work

Turn on **Update after render**, then render through NVK as usual. Leave Relay running. After a completed output is stable, Relay finds and verifies its matching sound, replaces the original, requests conversion, and verifies the converted file. The compact panel starts at 440 × 300 and can be resized/docked using ReaImGui's normal window controls.

**Wwise audio updated** means the replacement's bytes were verified, Wwise returned no conversion warnings/errors, and converted media passed a file check. **Show in Wwise** selects the updated parent container; if several were updated, choose one from the list. Your existing **Connect to Remote Platform** workflow remains in Wwise. Relay does not claim it has verified what played in the game.

An unmatched or ambiguous render is skipped. A failure pauses further replacements and lists any files that were not processed. Fix the cause and use **Retry skipped / failed files**, or re-enable and render again. If conversion fails after replacement, the new original remains in place. There is no rollback: **no previous-WAV backup is created**, as requested.

### Scope and limits

- No imports, object creation/deletion, project saves, SoundBank generation, conversion-setting changes or source-control checkout. The existing original and its converted cache are the intended changes.
- Exact project identity, unique sound name, source ID, parent, active source, original path and destination content are checked. Wrong projects, shared originals, read-only files, missing files and channel-count changes are rejected. The current original is hashed immediately before each replacement; if it changes during staging, replacement is rejected. Earlier edits are not remembered as conflicts between renders.
- Standard local RIFF WAV files only: PCM, float or extensible. No network paths, symbolic links/junctions, RF64/BW64, localized voice audio or semicolons in paths in this release. Render to a separate folder, not directly into Wwise Originals.
- Detection uses REAPER's latest completed `RENDER_STATS` report plus the listed files' timestamps/size. This is not a direct NVK callback. If NVK runs several native render groups before deferred scripts resume, only the final group's report may be visible. **Test your multi-group NVK workflow before relying on batch coverage.** Check the reported count against your outputs.
- A manual edit to a WAV still named in the last render report can also look like a new render. Pause Relay while externally editing those files. Merely opening Relay or enabling it establishes a baseline and does not replay old renders.
- Updates are sequential, not a batch transaction. Successful earlier files remain updated if a later one fails. Wwise/REAPER operations and large file hashing can briefly block the UI. Do not rename/reorganize the matched Wwise objects while a batch is updating.

Settings stay locally in REAPER's extension settings, keyed to the REAPER project’s master-track ID. The generated helper and local inspection-session files live in REAPER's resource folder under `Data/WwiseRelay`. Temporary audio contains only the new rendered bytes and is removed after replacement; it is not a backup of the old WAV.

### Development

Edit `src/`, then run `python tools/build.py` to rebuild the root Lua deliverable. Run `python -m pip install lupa==2.8` and `python tests/run_tests.py` for Lua checks. On Windows, run `powershell -NoProfile -File tests/test_windows.ps1` for synthetic file checks. No tests connect to a game or production project.

References: [REAPER ReaScript API](https://www.reaper.fm/sdk/reascript/reascripthelp.html), [Audiokinetic's ReaWwise Lua API overview](https://www.audiokinetic.com/en/blog/waapi-in-reascript-lua-with-reawwise/), [ReaWwise source](https://github.com/audiokinetic/ReaWwise).
