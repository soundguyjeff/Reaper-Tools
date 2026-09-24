"""Validate package paths, immutable bytes, action registration and release metadata."""
from pathlib import Path,PurePosixPath
from urllib.parse import urlparse,unquote
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1];feed=ET.parse(root/'index.xml').getroot()
assert feed.tag=='index' and feed.get('version')=='1' and feed.get('name')=='Reaper Tools'
allow_unreleased='--allow-unreleased' in sys.argv
entries={Path(e['file']).name:e for e in json.loads((root/'jeff-packages.json').read_text(encoding='utf-8'))['packages']}
seen=set();targets={};source_count=0
for category in feed.findall('category'):
    category_name=category.get('name');assert category_name in ('Game Audio','Jeff')
    for package in category.findall('reapack'):
        name=package.get('name');key=(category_name,name);assert key not in seen;seen.add(key)
        assert package.get('type')=='script' and name.endswith('.lua')
        entry=entries.get(name) if category_name=='Jeff' else None
        if entry:assert entry['enabled'],f'An explicitly held script is installable: {name}'
        else:assert category_name=='Game Audio' and name=='Wwise Relay.lua'
        filename=entry['file'] if entry else name;versions=set()
        for version in package.findall('version'):
            ver=version.get('name');assert ver not in versions;versions.add(ver)
            sources=version.findall('source');mains=[s for s in sources if s.get('main')=='main'];assert len(mains)==1
            assert (mains[0].get('platform') is None) if entry else (mains[0].get('platform')=='win64')
            for source in sources:
                parsed=urlparse(source.text)
                assert parsed.scheme=='https' and parsed.netloc=='raw.githubusercontent.com'
                assert not parsed.query and not parsed.fragment and not parsed.username and not parsed.password
                parts=unquote(parsed.path).strip('/').split('/')
                assert parts[:2]==['soundguyjeff','Reaper-Tools'] and re.fullmatch('[0-9a-f]{40}',parts[2])
                source_file='/'.join(parts[3:]);expected=filename if source is mains[0] else 'licenses/GPL-3.0.txt'
                assert source_file==expected
                data=subprocess.check_output(['git','show',parts[2]+':'+source_file],cwd=root)
                assert source.get('hash')=='1220'+hashlib.sha256(data).hexdigest()
                if not entry:assert re.search(rb'^-- @version (\S+)',data,re.M)[1].decode()==ver
                target=source.get('file',name);target_path=PurePosixPath(target)
                assert not target_path.is_absolute() and '..' not in target_path.parts
                target_key=(category_name+'/'+target).casefold()
                assert targets.setdefault(target_key,key)==key,'Packages overwrite one another'
                source_count+=1
            if entry and entry.get('license')=='GPL-3.0':assert len(sources)==2
        current=entry['version'] if entry else re.search(rb'^-- @version (\S+)',(root/filename).read_bytes(),re.M)[1].decode()
        assert current in versions or allow_unreleased
        if current in versions:
            version=next(v for v in package.findall('version') if v.get('name')==current)
            assert version.find("source[@main='main']").get('hash')=='1220'+hashlib.sha256((root/filename).read_bytes()).hexdigest()
expected={('Jeff',name) for name,e in entries.items() if e['enabled']}|{('Game Audio','Wwise Relay.lua')}
assert seen<=expected
assert seen==expected or allow_unreleased
print(f'ReaPack: {len(seen)} packages and {source_count} historical files verified; paths, action registration, immutable URLs and checksums passed.')
