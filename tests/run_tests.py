from pathlib import Path
from lupa.lua54 import LuaRuntime
import subprocess, sys

root=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'tools/build.py')],check=True)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT=str(root)
lua.execute("package.path = ROOT .. '/src/?.lua;' .. package.path")
for name in ('core','wwise','files'):
    lua.execute("package.preload['relay.' .. ...] = assert(loadfile(ROOT .. '/src/' .. ... .. '.lua'))",name)
lua.execute("assert(loadfile(ROOT .. '/Wwise Relay.lua'))")
count=lua.execute((root/'tests/test_core.lua').read_text(encoding='utf-8'))
print(f'Bundle syntax and {count} safety tests passed.')
matching_count=lua.execute((root/'tests/test_matching.lua').read_text(encoding='utf-8'))
print(f'{matching_count} automatic Wwise resolver tests passed.')
app_count=lua.execute((root/'tests/test_app.lua').read_text(encoding='utf-8'))
print(f'{app_count} simulated panel workflows passed (no live REAPER or Wwise).')
