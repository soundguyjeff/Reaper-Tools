"""Packaging checks only: compile scripts without running any REAPER actions."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
import hashlib,json
root=Path(__file__).resolve().parents[1]
entries=json.loads((root/'jeff-packages.json').read_text(encoding='utf-8'))['packages']
assert len(entries)==47 and len({e['file'] for e in entries})==47
assert {p.relative_to(root).as_posix() for p in (root/'Jeff').glob('*.lua')}=={e['file'] for e in entries}
lua=LuaRuntime(unpack_returned_tuples=True)
check=lua.eval('function(path)local fn,err=loadfile(path);return fn~=nil,err end')
for entry in entries:
    path=root/entry['file'];data=path.read_bytes()
    assert hashlib.sha256(data).hexdigest()==entry['imported_sha256'],f'Imported file changed: {path.name}'
    ok,error=check(str(path));assert ok,(path.name,error)
    if not entry['enabled']:assert entry['notes']
print(f"PASS {len(entries)} Lua scripts match their imported bytes and compile without execution")
print(f"PASS {sum(e['enabled'] for e in entries)} installable and {sum(not e['enabled'] for e in entries)} held entries have explicit metadata")
