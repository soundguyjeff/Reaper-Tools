# Wwise Relay: first Windows check

No remote access or internet connection is required at runtime. These checks are manual; you do not need to run any developer commands.

Start with one disposable existing SFX in a test project. Relay intentionally keeps no WAV backup.

1. **Open:** Load the script and confirm the compact panel opens without an error. Connect to Wwise 2024.1.1, pin the project and choose the correct platform.
2. **Link:** Select that sound's active audio source in Wwise. Link its existing rendered WAV in Relay. Check the displayed object path. Merely saving the link must not change the original audio.
3. **Enable:** Turn on Update after render. Old renders must not be sent immediately.
4. **Render:** Make an obvious audible change and render through your usual NVK action. After the render finishes, expect “1 replaced + converted” and “Wwise audio updated.” Check the result in Wwise, then through your existing remote game connection.
5. **Locate:** Click Show in Wwise. The sound's immediate parent container should be selected. Repeat with outputs from two containers and check the container selector.
6. **Repeat:** Render the same filename again, including a same-duration change. Confirm another update occurs. Also try an unchanged render: an already-current converted cache should be accepted.
7. **Batch:** Render several linked WAVs in one NVK operation, especially across different NVK render groups. Check **every expected filename and the count** in Show file results. REAPER exposes only its latest render report, so this check determines whether your NVK configuration reports the complete batch.
8. **Cancel:** Cancel a render. No incomplete WAV should be sent. Check that any earlier completed groups are accurately reported and that canceled outputs were not replaced.
9. **Unknown output:** Render an unlinked filename. Expect Skipped; no Wwise objects or originals should be created.
10. **Wrong project / unavailable Wwise:** Close Wwise or open a different project, then render. Expect paused updates with a useful error, not success.
11. **Read-only original:** With a disposable original marked read-only, render again. Relay should stop without forcing the file writable. Restore normal permissions using your usual workflow afterward.
12. **Failure visibility:** If Wwise rejects conversion, Relay must say conversion failed and leave updates paused. The replacement has already happened; no backup or automatic undo exists. Fix the conversion issue and retry.

If a check fails, capture the exact message, REAPER/NVK/ReaWwise/ReaImGui versions, and whether it was a single render or multiple NVK groups. You can redact project names and paths; audio/project files are not needed to report a problem.

Do not treat a successful panel notification as proof that the game played the new media: verify that once through the remote connection. Relay stops at the Wwise conversion boundary by design.
