"""Validate feed metadata and exact committed package bytes without accessing a project."""
from pathlib import Path
from urllib.parse import urlparse, unquote
import hashlib, re, subprocess, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
feed=ET.parse(root/'index.xml').getroot()
assert feed.tag=='index' and feed.get('version')=='1' and feed.get('name')=='Reaper Tools'
packages=feed.findall('./category/reapack')
assert len(packages)==1
package=packages[0]
assert package.get('type')=='script' and package.get('name')=='Wwise Relay.lua'
versions=set()
for version in package.findall('version'):
    name=version.get('name');assert name not in versions;versions.add(name)
    sources=version.findall('source');assert len(sources)==1
    source=sources[0]
    assert source.get('main')=='main' and source.get('platform')=='win64'
    parsed=urlparse(source.text)
    assert parsed.scheme=='https' and parsed.netloc=='raw.githubusercontent.com'
    assert not parsed.query and not parsed.username and not parsed.password
    parts=unquote(parsed.path).strip('/').split('/')
    assert parts[:2]==['soundguyjeff','Reaper-Tools'] and re.fullmatch('[0-9a-f]{40}',parts[2])
    filename='/'.join(parts[3:]);assert filename=='Wwise Relay.lua'
    data=subprocess.check_output(['git','show',parts[2]+':'+filename],cwd=root)
    assert source.get('hash')=='1220'+hashlib.sha256(data).hexdigest()
    assert re.search(rb'^-- @version (\S+)',data,re.M)[1].decode()==name
latest=(root/'Wwise Relay.lua').read_bytes()
assert re.search(rb'^-- @version (\S+)',latest,re.M)[1].decode() in versions
print('ReaPack feed: version, Windows platform, action registration, immutable URLs and checksums passed.')
