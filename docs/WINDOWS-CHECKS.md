# Wwise Relay v0.3.5: Windows check

No remote access or internet connection is required at runtime. These checks are manual; you do not need to run any developer commands.

Start with one disposable existing SFX in a test project. Relay intentionally keeps no WAV backup.

1. **Open:** Load the script and confirm the compact panel opens without an error. Wait for the automatic connection to Wwise 2024.1.1, pin the project and choose the correct platform.
2. **Name:** Give the rendered WAV the same name as the existing Wwise Sound (for example, `Explosion_01.wav` and `Explosion_01`). Do not set up a link or select the sound in Wwise. Merely connecting/enabling must not change the original audio.
3. **Enable:** Turn on Update after render. Old renders must not be sent immediately. No PowerShell or terminal window should appear during file checks. The inspector is reused, and stops when Relay is paused or closed.
4. **Render:** Make an obvious audible change and render through your usual NVK action. Confirm Show file results lists the intended Wwise Sound path. After the render finishes, expect “1 replaced + converted” and “Wwise audio updated.” Check the result in Wwise, then through your existing remote game connection.
5. **Locate:** Click Show in Wwise. The sound's immediate parent container should be selected. Repeat with outputs from two containers and check the container selector.
6. **Repeat:** Render the same filename again, including a same-duration change. Confirm another update occurs. Also try an unchanged render and then revert to an earlier version: a matching existing conversion should be accepted. A rapid repeat can take up to two additional seconds for a distinct file timestamp.
7. **Batch:** Render several WAVs with matching sound names in one NVK operation, especially across different NVK render groups. Check **every expected filename and the count** in Show file results. REAPER exposes only its latest render report, so this check determines whether your NVK configuration reports the complete batch.
8. **Cancel:** Cancel a render. No incomplete WAV should be sent. Check that any earlier completed groups are accurately reported and that canceled outputs were not replaced.
9. **Unknown output:** Render a filename that has no matching Wwise Sound. Expect Skipped; no Wwise objects or originals should be created.
10. **Wrong project / unavailable Wwise:** Close Wwise or open a different project, then render. Expect paused updates with a useful error, not success.
11. **Read-only original:** With a disposable original marked read-only, render again. Relay should stop without forcing the file writable. Restore normal permissions using your usual workflow afterward.
12. **Failure visibility:** If Wwise rejects conversion, Relay must say conversion failed and leave updates paused. The replacement has already happened; no backup or automatic undo exists. Fix the conversion issue and retry.

13. **Duplicate names:** In a disposable project, give two existing Sounds the same name in different containers. Render that filename. Expect Skipped with an ambiguity message, and neither original replaced. Also check that two render outputs with the same stem from different folders in one reported batch are both skipped.
14. **No saved links:** Render a second, never-before-used filename that matches another existing unique Sound. It should be found automatically without setup.

15. **Inspection errors:** In a disposable test, leave a reported WAV missing/unreadable/incomplete. After roughly eight seconds of failed checks, expect the exact filename and error in Relay, with updates paused. A briefly locked file that becomes readable within that interval should proceed normally.

16. **Dropbox/cloud paths:** With a rendered WAV available offline in your normal Dropbox folder, confirm it can be inspected and updated. If a path is still rejected, the message should identify the exact link or show an unsupported marker code. Automated tests cover the cloud-tag classifier and real Windows junctions; they do not run Dropbox itself.

17. **Responsiveness:** Open Relay with Wwise closed or the port incorrect. REAPER should remain usable and Relay must show an error instead of hanging. While waiting, try Stop waiting. After Wwise becomes available and connects automatically, confirm REAPER stays usable during file checking and conversion. Stopping does not undo a WAV already replaced or cancel a conversion already sent to Wwise.

18. **Automatic connection:** Start Relay before Wwise. It should display Waiting for Wwise and retry without clicks or popups. Open the saved Wwise project and wait for Connected. Confirm an unrelated project is not accepted. Stop waiting must pause retries; Resume auto-connect restarts them. Connecting/reconnecting alone must never replace audio.

19. **Nested originals:** Try a Sound whose original WAV is inside a subfolder of Originals/SFX, including an AudioFileSource whose name differs from its WAV filename. Confirm the same source, original path and subfolder remain in use, with no extra files or objects.
20. **Large project:** Start with a small render batch. Matching should send only targeted results to Relay, but Wwise's own query time depends on the project. If it reaches the one-minute lookup limit, Relay must report that lookup and pause without claiming a conversion happened.

If a check fails, capture the exact message, REAPER/NVK/ReaWwise/ReaImGui versions, and whether it was a single render or multiple NVK groups. You can redact project names and paths; audio/project files are not needed to report a problem.

Do not treat a successful panel notification as proof that the game played the new media: verify that once through the remote connection. Relay stops at the Wwise conversion boundary by design.

17. **Linked project root:** Open a test Wwise project through a local directory junction such as `C:\Phobos`. Render to a separate folder. Confirm one matched existing source updates and converts, and unrelated originals remain unchanged. Also test a render folder reached through a directory junction.

18. **Source-control checkout:** With Wwise source control connected, render an update to a matched read-only original. Confirm only that WAV checks out and updates. Check a locked/unavailable file fails without replacement.
19. **Default enabled:** Restart Relay with a saved project. Confirm Update after render enables automatically without replaying the previous render; disconnect or manually pause and confirm it stays paused.

20. **Native batch timing:** Render 10 small matched WAVs together; measure from render completion to conversion confirmation. Confirm one native import/conversion batch, no separate checkout UI from Relay, unchanged WWU save behavior, and unchanged unrelated audio. Repeat with a Perforce-locked WAV; report native import errors rather than success.
