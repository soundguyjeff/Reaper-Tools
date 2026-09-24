from pathlib import Path
import zipfile
root=Path(__file__).resolve().parents[1]
with zipfile.ZipFile(root/'Wwise-Relay.zip','w',compression=zipfile.ZIP_DEFLATED) as z:
    for name in ('Wwise Relay.lua','README.md','docs/WINDOWS-CHECKS.md','docs/REAPACK.md'):
        info=zipfile.ZipInfo(name, date_time=(2026,9,24,0,0,0))
        info.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(info,(root/name).read_bytes())
print('Built Wwise-Relay.zip')
