#!/usr/bin/env python3
"""Build the single-file REAPER deliverable using only Python's standard library."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
header = '''-- @description Wwise Relay - update existing Wwise audio after REAPER/NVK renders
-- @version 0.1.0
-- @author Reaper Tools
-- @about Windows; Wwise 2024.1.1; requires ReaWwise and ReaImGui 0.9.3+.
-- Generated from src/. Single-file install: load this file in REAPER's Actions list.
-- No Wwise objects are created, no audio is imported, no WAV backups are made.
'''
parts = [header]
for name in ('core', 'wwise', 'files'):
    parts.append(f"package.preload['relay.{name}'] = function()\n" + (ROOT/'src'/f'{name}.lua').read_text() + '\nend\n')
worker = (ROOT/'src/windows.ps1').read_text()
assert ']====]' not in worker
parts.append("package.preload['relay.worker'] = function() return [====[\n" + worker + ']====] end\n')
parts.append((ROOT/'src/app.lua').read_text())
target = ROOT/'Wwise Relay.lua'
target.write_text('\n'.join(parts), encoding='utf-8', newline='\n')
print(f'Built {target.name}: {target.stat().st_size:,} bytes')
