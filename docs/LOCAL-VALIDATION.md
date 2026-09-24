# Wwise Relay v0.3.5 native batching

[Windows validation passed](https://github.com/soundguyjeff/Reaper-Tools/actions/runs/36060354097): existing Lua/panel/bridge/file checks and the native batch tests. Ten-file and shared-original cases use exactly 10 Wwise calls, one import and one conversion. A stale render prevents import.

Live Wwise 2024.1.1 test: 10-file native batch completed in 0.638 seconds with filesystem translation for the Mac/Wine test host. Source IDs/parents/names/original paths, unrelated WAV hashes, and the set of original WAV files were preserved. No new sources or originals. The fixture contains about 20,000 synthetic Sounds. No Perforce provider/server is available, and the user's million-asset Windows project was not benchmarked.

The earlier native single-file probe completed in 6 ms; a read-only WAV with automatic checkout disabled was rejected by Wwise. Therefore this release allows the native importer to obtain necessary WAV access, without separate SourceControlCheckoutWAV calls, project saves, or WWU checkout commands. It does not claim that WAV checkout can always wait until Save.

46 core Lua, 16 resolver, 6 conversion and 28 simulated panel workflows pass locally. Windows native batch mock checks require one import and conversion for 10 files, shared-original exclusion, and no import for a stale render.

# Wwise Relay v0.3.4

[Windows validation passed](https://github.com/soundguyjeff/Reaper-Tools/actions/runs/36058091403): Lua, simulated panel, real asynchronous bridge, 37 file checks, and 5 scoped checkout mock cases on Windows PowerShell 5.1.

Local tests: 46 core, 16 resolver, 6 conversion, 30 simulated panel workflows and 5 scoped checkout cases passed. Checkout mocks cover success, wrong project, shared original, still-read-only and changed audio. The real Wwise 2024.1.1 command inventory includes SourceControlCheckoutWAV. A real Perforce/source-control server is not available here; provider login, permissions and locks must be verified in the user environment.

# Wwise Relay v0.3.3 validation

- 46 core Lua checks, 16 resolver checks, 6 conversion checks and 27 simulated panel workflows passed.
- 30 PowerShell file checks passed on macOS. These do not execute Windows kernel calls.
- Embedded Windows C# path resolver compiled successfully on macOS.
- Added Windows-only regressions for resolving a real directory junction, replacing an existing WAV through it, same-file aliases, retargeted junctions and missing files. All passed on Windows PowerShell 5.1 in [run 36056849578](https://github.com/soundguyjeff/Reaper-Tools/actions/runs/36056849578); 37 file checks passed.
- Windows asynchronous bridge checks passed: 3,248 simulated REAPER frames, worst observed step 15 ms. No real Windows/NVK or live Wwise end-to-end validation is claimed for v0.3.3.

## Previous release evidence

# Wwise Relay v0.3.2 validation

## Real Wwise test

Tested with installed Wwise 2024.1.1 build 8691 Authoring on macOS, using its real WAAPI connection and Windows conversion platform. The isolated RelayTest project contains 20,000 unrelated empty Sounds and nine audio test Sounds. The Lua resolver, PowerShell WAMP client, file replacement, source refresh and conversion checks are the production implementations. Only launching PowerShell and translating Wine filesystem paths are adapted for Mac.

Confirmed:

- Exact Sound-name matching, including Unicode and original filenames that differ from Sound names.
- Missing names, duplicate names and shared originals are skipped.
- Changed, unchanged, reverted and previously unconverted tones produce the expected converted PCM samples. Tests compare the rendered WAV's sample bytes with the converted WEM's sample bytes.
- Metadata-only WAV changes also pass, with identical converted sample data.
- Source IDs, names, parent containers and original paths remain unchanged. Nested originals and deliberately renamed AudioFileSources work. Unrelated original WAV hashes remain unchanged.
- A refresh aimed at a nonexistent source GUID is refused by Wwise without creating a source.
- Show in Wwise selects the successful Sound's parent container; verified in the Wwise interface.
- The background worker completes over 1,100 simulated REAPER frames with the longest observed main-thread step approximately 6 ms. This measures the real worker plus Lua integration harness, not REAPER/NVK itself.

The stale conversion originally reproduced with both Relay and Audiokinetic's Python client: an external WAV overwrite could leave Wwise reporting the previous cache file despite an empty conversion error list. The repair explicitly refreshes the one existing source from its own original, preserves its Originals/SFX subfolder, ensures distinct timestamps for rapid overwrites, waits for changed audio content identity, and checks the converted WEM's embedded identity. General audio imports remain blocked. Cache age alone is no longer used: returning to older audio can legitimately reuse an older cache file.

## Large-project matching

Relay requests exact Sound-name matches, reads the active source by ID, and requests owners of that particular original WAV. It no longer downloads all Sounds and AudioFileSources into REAPER after a render. Each verification uses fresh targeted queries; duplicate names and shared originals still cause a skip. Filtered searches have a one-minute timeout and run outside REAPER's UI thread.

Individual measurements from the real Wwise HTTP interface:

| Request | Returned objects | Response bytes | Elapsed |
| --- | ---: | ---: | ---: |
| Previous full Sound query | 20,007 | 7,913,435 | 516 ms |
| Exact Sound-name query | 1 | 244 | 34 ms |
| Duplicate-name query | 2 | 508 | 34 ms |

These measurements preceded the two additional edge-case Sounds. They are not latency guarantees. Most test Sounds have no audio sources, so this does not establish ownership-query scaling across millions of AudioFileSources. Wwise may still scan internally when evaluating a filter; million-asset project performance has not been measured.

## Automated checks

- 46 core safety checks, 16 matching checks, six conversion-freshness checks and 27 simulated panel workflows.
- 29 synthetic file checks on Mac (32 on Windows, including junction checks): replacement byte equality, conflicts, locks, read-only files, missing destinations, malformed WAVs, channel changes, unchanged unrelated files, hidden cache files, WEM identity, metadata-only changes and Cloud Files tag classification. Windows additionally checks actual junctions.
- Real background-worker tests with a local WAMP test peer: fragmented/error/stalled replies, exact existing-source refresh payload and subfolder, wrong project, missing/changed/shared sources, refresh errors, unexpected results, forbidden general imports, expired writes and stop/restart.
- The GitHub Windows workflow runs the worker with Windows Script Host and Windows PowerShell 5.1. The [v0.3.2 candidate run](https://github.com/soundguyjeff/Reaper-Tools/actions/runs/36053335518) passed: all 32 Windows file checks, all Lua checks and the real asynchronous bridge tests. The bridge advanced 3,566 simulated REAPER frames with a longest observed step of 16 ms. The release feed is published after this successful run.

Reproduce the live check only against the prepared disposable fixture:

```
python tests/test_live_wwise.py --fixture /path/to/wwise-live --powershell /path/to/pwsh
```

`--matching-only` performs read-only matching. Full mode replaces synthetic originals and generates synthetic render variants. It refuses a different project name/path or an Originals directory outside the fixture. Do not point it at a production project.

## Remaining environment checks

Native Windows REAPER 7.78/NVK rendering, complete NVK multi-group output coverage, Dropbox provider behavior, a million-asset production project and the game's remote connection are not established by these tests. The tool intentionally stops at Wwise conversion. Use the short [Windows check guide](WINDOWS-CHECKS.md) for the closed PC.
