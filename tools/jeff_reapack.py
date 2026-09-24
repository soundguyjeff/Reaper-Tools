"""Index committed, unmodified local scripts using separate package metadata."""
from pathlib import Path
from urllib.parse import quote
import hashlib,json,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def append_jeff(root):
    manifest=ROOT/'jeff-packages.json'
    if not manifest.exists():return
    entries=json.loads(manifest.read_text(encoding='utf-8'))['packages']
    category=root.find("category[@name='Jeff']")
    if category is None:category=ET.SubElement(root,'category',name='Jeff')
    for entry in entries:
        if not entry['enabled']:continue
        filename=entry['file'];data=(ROOT/filename).read_bytes()
        commit=git('log','-1','--format=%H','--',filename).decode().strip()
        if not commit or git('show',f'{commit}:{filename}')!=data:
            raise SystemExit(f'Commit {filename} before updating ReaPack.')
        name=Path(filename).name
        package=next((p for p in category.findall('reapack') if p.get('name')==name),None)
        if package is None:package=ET.SubElement(category,'reapack',name=name,type='script',desc=entry['description'])
        package.set('desc',entry['description'])
        metadata=package.find('metadata')
        if metadata is None:metadata=ET.SubElement(package,'metadata')
        link=metadata.find('link')
        if link is None:link=ET.SubElement(metadata,'link',rel='website',href='https://github.com/soundguyjeff/Reaper-Tools/blob/main/docs/JEFF-SCRIPTS.md')
        link.text='Installation, requirements and existing shortcuts'
        description=metadata.find('description')
        if description is None:description=ET.SubElement(metadata,'description')
        text='Unmodified script from Jeff\'s local collection. Syntax checked; behavior has not been audited. Existing script credits are retained.'
        if entry['requirements']:text+=' Requires: '+ '; '.join(entry['requirements'])+'.'
        if entry['notes']:text+=' '+' '.join(entry['notes'])
        text+=' Installing does not migrate shortcuts from older local copies.'
        # RTF remains ASCII, even for Unicode titles or user notes.
        escaped=text.replace('\\','\\\\').replace('{','\\{').replace('}','\\}')
        escaped=''.join(c if ord(c)<128 else '? ' for c in escaped)
        description.text=r'{\rtf1\ansi '+escaped+'}'
        release=package.find(f"version[@name='{entry['version']}']")
        digest='1220'+hashlib.sha256(data).hexdigest()
        if release is not None:
            if release.find("source[@main='main']").get('hash')!=digest:
                raise SystemExit(f"Bump {filename}'s version before releasing changed bytes.")
            continue
        stamp=git('show','-s','--format=%cI',commit).decode().strip()
        release=ET.SubElement(package,'version',name=entry['version'],author=entry['author'],time=stamp)
        ET.SubElement(release,'source',main='main',hash=digest).text=f'https://raw.githubusercontent.com/soundguyjeff/Reaper-Tools/{commit}/{quote(filename)}'
        if entry.get('license')=='GPL-3.0':
            license_file='licenses/GPL-3.0.txt';license_data=git('show',f'{commit}:{license_file}')
            ET.SubElement(release,'source',file='Licenses/'+Path(filename).stem+'.GPL-3.0.txt',hash='1220'+hashlib.sha256(license_data).hexdigest()).text=f'https://raw.githubusercontent.com/soundguyjeff/Reaper-Tools/{commit}/{license_file}'
        ET.SubElement(release,'changelog').text='First ReaPack publication of this local copy. Script contents and filename unchanged.'
    print(f"Jeff collection: {sum(e['enabled'] for e in entries)} installable packages; {sum(not e['enabled'] for e in entries)} held for repair.")
