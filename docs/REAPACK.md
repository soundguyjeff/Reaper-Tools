# Install through ReaPack

The repository includes `index.xml` with **Wwise Relay 0.1.1**, including the startup fix for REAPER 7.78 Win64. ReaPack registers the script in REAPER's main Actions list. The package is marked for Windows x64.

## Repository access

The repository is currently private. The normal GitHub raw-file URL below is **not usable as an unauthenticated ReaPack feed while it remains private**. Signing into GitHub in a browser does not sign ReaPack in. Both the index and the Lua download need to be reachable by ReaPack.

A public repository or a separate public distribution repository can provide the simple install/update link. Changing visibility requires the owner's approval. No account tokens are embedded in this index or the package.

Once this repository is publicly accessible, import:

```
https://raw.githubusercontent.com/soundguyjeff/Reaper-Tools/main/index.xml
```

## Install and update

1. In REAPER, choose **Extensions → ReaPack → Import repositories** and paste the accessible feed URL.
2. Choose **Extensions → ReaPack → Browse packages** and search for **Wwise Relay**.
3. Right-click the package, choose **Install**, then **Apply**.
4. Run **Wwise Relay** from REAPER's Actions list.

Install **ReaWwise** and **ReaImGui 0.9.3+** separately through their normal ReaPack packages. This feed contains Relay only and does not automatically install those dependencies.

For later updates, close Relay first, choose **ReaPack → Synchronize packages**, apply the update, then run Relay again.

If you already loaded a manual copy, stop it before running the ReaPack copy. Point your toolbar/shortcut at the new ReaPack action so you do not keep launching the old file. ReaPack does not remove your manually installed copy. Project-link settings stay in REAPER's settings.

ReaPack needs network access for online installation and updates. Relay itself runs locally afterward. A closed PC with no permitted network path still needs your approved offline transfer process.

## Maintaining the feed

1. Bump the script version, rebuild it with `python tools/build.py`, run validation, and commit the Lua deliverable.
2. Run `python tools/reapack.py`, then `python tests/test_reapack.py`.
3. Commit the updated `index.xml` and publish when authorized.

Each release URL points to a fixed commit, with a SHA-256 checksum. Existing versions retain their original bytes. The initial feed intentionally omits v0.1.0 because its startup call is broken. `tools/reapack.py` retains older valid versions when appending new ones.

Format reference: [ReaPack's official index specification](https://github.com/cfillion/reapack/wiki/Index-Format).
