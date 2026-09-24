# Jeff scripts on ReaPack

47 Lua files were copied from Jeff's supplied local collection without changing their contents or filenames. The Dropbox originals were not moved, edited or deleted. Existing author and license notices remain in each source.

## Install

Use the existing **Reaper Tools** repository in ReaPack. Synchronize packages, open **Browse packages**, filter to **Reaper Tools** and category **Jeff**, then select the scripts you want and choose **Install → Apply**. There are 44 installable scripts; three obvious problem scripts are archived in Git only, pending repair. The separate EEL file was not part of this Lua upload.

Feed: `https://raw.githubusercontent.com/soundguyjeff/Reaper-Tools/main/index.xml`

Lua packages have no platform filter. This makes them available on Mac and Windows; it does not establish that their behavior has been tested on either. Wwise Relay keeps its Windows-only package and existing release history.

## Existing shortcuts

**Keep your original scripts where they are.** Copying them into this repository and installing through ReaPack does not delete your existing keyboard assignments. However, the existing actions point at `Scripts/Jeff/...`, while these packages install at `Scripts/Reaper Tools/Jeff/...`. Those are separate actions: your old shortcuts continue to execute the old files. ReaPack updates only its managed copies.

Moving or deleting the old files before migrating the actions can break shortcuts, toolbar buttons and custom actions. No shortcut migration or REAPER configuration editing was performed as part of this upload. Keep the originals until that migration has been completed and checked. Avoid assigning the same shortcut to both copies by accident.

ReaPack's developer also documents that changing a script's installation location can affect existing custom actions: [installation-path discussion](https://forum.cockos.com/showthread.php?t=175089).

## Requirements

The following requirements were identified in the code. Presets and extensions are not bundled or automatically installed.

| Script | Requirements |
| --- | --- |
| 100 HPF.lua | ReaEQ; Saved REAPER FX preset: Jeff - 100 HPF (not included) |
| 140 HPF.lua | ReaEQ; Saved REAPER FX preset: Jeff - 140 HPF (not included) |
| 8k LPF.lua | ReaEQ; Saved REAPER FX preset: Jeff - 8k LPF (not included) |
| HPF LPF.lua | ReaEQ; Saved REAPER FX preset: Jeff - HPF LPF (not included) |
| Hi Boost.lua | ReaEQ; Saved REAPER FX preset: Jeff - Hi Boost (not included) |
| Jeff_Copy Take Pan Down.lua | SWS extension |
| Jeff_Hide All Take Envelopes.lua | SWS extension |
| Jeff_Move Edit Cursor for Media Item Top Half.lua | SWS extension |
| Jeff_Nudge Edit Cursor Left - Saved Dialog Settings 1.lua | Existing SWS/Saved Nudge 1 Distance extension setting used by this local script |
| Jeff_Nudge Left - 1 Frame - PT Style.lua | SWS extension |

## Held for repair

These files remain byte-for-byte copies in Git but have no ReaPack package. The reasons below are based on direct code inspection and comparison with the [native REAPER API](https://www.reaper.fm/sdk/reascript/reascripthelp.html). No script was run against an editing session.

- **Jeff_Gang Item FX Parameters - Toggle On Off.lua**: Known issue: an unbounded while loop can freeze REAPER; also targets track FX rather than take FX. Repair before use.
- **Jeff_Nudge Edit Cursor Left - 1 Frame.lua**: Known issue: calls Snap_GetGrid, which is not a native REAPER API. Needs repair before use.
- **Toggle Width.lua**: Known issue: calls CreateTrackEnvelope and GetSetEnvelopeName, which are not native REAPER APIs. Needs repair before use.

## What was checked

All 47 Lua files compile and match the original file hashes. The package index is checked for immutable download links, encoded special characters (including marker filenames containing `#`), source checksums, correct Action List registration and file ownership conflicts. This is packaging validation, not a behavioral audit of the scripts; existing logic, parameter settings and any other pre-existing issues are unchanged.

## Credits and licenses

Original source credits are retained, including X-Raym, Lokasenna and ChatGPT where named. Scripts already carrying GPL v3 notices include a copy of that license in their ReaPack package under a unique `Licenses/` filename. The bundled license text comes from the [SPDX license data](https://github.com/spdx/license-list-data/blob/main/text/GPL-3.0-only.txt). No new blanket license has been imposed on the collection.

## Future updates

The authoritative copies for ReaPack releases are now the files in this repository's `Jeff/` folder. Changes made only in Dropbox do not automatically publish. Package versions, dependencies and credits live in `jeff-packages.json` so the imported scripts can stay unchanged. Update the applicable script and manifest version, validate, commit the script, then run `python tools/reapack.py` and `python tests/test_reapack.py`. Commit and publish the resulting feed when authorized. Existing published versions remain pinned to their original commits.
