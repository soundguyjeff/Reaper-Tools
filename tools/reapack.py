#!/usr/bin/env python3
"""Append the committed Lua release to the ReaPack feed. Existing versions are immutable."""
from pathlib import Path
import hashlib, re, subprocess, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
REPO='soundguyjeff/Reaper-Tools'
FILE='Wwise Relay.lua'
def git(*args):
    return subprocess.check_output(['git',*args],cwd=ROOT)
def main():
    commit=git('log','-1','--format=%H','--',FILE).decode().strip()
    data=git('show',f'{commit}:{FILE}')
    if data!=(ROOT/FILE).read_bytes():
        raise SystemExit('Commit the rebuilt Lua deliverable before updating the feed.')
    version=re.search(rb'^-- @version (\S+)',data,re.M)[1].decode()
    digest='1220'+hashlib.sha256(data).hexdigest()
    url=f'https://raw.githubusercontent.com/{REPO}/{commit}/Wwise%20Relay.lua'
    path=ROOT/'index.xml'
    root=ET.parse(path).getroot() if path.exists() else ET.Element('index',version='1',name='Reaper Tools')
    category=root.find("category[@name='Game Audio']")
    if category is None: category=ET.SubElement(root,'category',name='Game Audio')
    package=category.find("reapack[@name='Wwise Relay.lua']")
    if package is None:
        package=ET.SubElement(category,'reapack',name=FILE,type='script',desc='Wwise Relay - update existing Wwise audio after rendering')
        meta=ET.SubElement(package,'metadata')
        ET.SubElement(meta,'link',rel='website',href=f'https://github.com/{REPO}').text='Setup and instructions'
    meta=package.find('metadata')
    description=meta.find('description')
    if description is None: description=ET.SubElement(meta,'description')
    description.text=(r'{\rtf1\ansi Wwise Relay for Windows x64.\par '
        r'Requires REAPER 7, ReaImGui 0.9.3+, Wwise 2024.1.1, Windows Script Host and PowerShell 5.1.\par '
        r'Automatically matches WAV filenames to unique existing Sound names. No manual audio links, new objects or WAV backups.\par '
        r'Test build: verify your NVK render groups before relying on batch coverage.}')
    release=package.find(f"version[@name='{version}']")
    if release is not None:
        if release.find('source').get('hash')!=digest:
            raise SystemExit('This version already has different bytes. Bump the Lua version first.')
    else:
        stamp=git('show','-s','--format=%cI',commit).decode().strip()
        release=ET.SubElement(package,'version',name=version,author='Reaper Tools',time=stamp)
        ET.SubElement(release,'source',main='main',platform='win64',hash=digest).text=url
        changes={
            '0.1.1':'Fix launch error caused by GetProjectGUID; use built-in REAPER identity functions. First ReaPack release.',
            '0.3.1':'Automatically connect to Wwise on startup and retry quietly with bounded backoff. Verify the saved project, monitor connection health, and allow Retry now or Resume auto-connect. Reconnection never re-enables or replays audio updates.',
            '0.3.0':'Move Wwise connection, WAAPI calls and all audio file operations into a background helper. Add timeouts, Stop waiting and cooperative panel processing. Remove synchronous ReaWwise dependency. Requires Windows Script Host and PowerShell 5.1.',
            '0.2.4':'Allow Windows Cloud Files markers in render/original paths while still rejecting actual symbolic links, junctions and unknown reparse tags. Report the exact unsupported path component.',
            '0.2.3':'Suppress Windows PowerShell first-use progress output in the hidden launcher. Includes persistent console-free file inspection and visible WAV errors.',
            '0.2.2':'Fix the Windows inspector startup hang by launching without inherited handles. Retain quiet persistent inspection and visible WAV errors.',
            '0.2.1':'Fix repeating PowerShell windows: reuse one read-only inspector created without a console. Surface failed WAV inspection details and pause instead of silently retrying forever.',
            '0.2.0':'Automatically match rendered WAV filenames to unique existing Wwise Sound names. Remove manual audio links. Skip missing, ambiguous, shared or competing targets. Keep project and platform preferences.'}
        ET.SubElement(release,'changelog').text=changes.get(version,'Updated Wwise Relay. See repository history for changes.')
    ET.indent(root,space='  ')
    path.write_bytes(ET.tostring(root,encoding='utf-8',xml_declaration=True)+b'\n')
    print(f'ReaPack feed ready: Wwise Relay {version}, pinned to {commit[:8]}')
if __name__=='__main__': main()
