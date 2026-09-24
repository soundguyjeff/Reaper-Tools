"""Read-only lookup comparison on the isolated local Wwise fixture."""
import argparse,json,statistics,subprocess,time,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--powershell',required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
def query(waql):
    req={'uri':'ak.wwise.core.object.get','args':{'waql':waql},'options':{'return':['id','name','type']}}
    with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8090/waapi',data=json.dumps(req).encode(),headers={'Content-Type':'application/json'}),timeout=30) as r:
        return json.load(r)['return']
assert query('from type Project')[0]['id']=='{51AB6C26-1F54-4836-A39E-C5834AC0F842}', 'Only the isolated fixture is permitted'
names=[f'Relay_Batch_{i:02d}' for i in range(1,11)]
edge=['Relay_Duplicate','Relay_Unmatched','Relay_Unicode_火','relay_batch_01','Relay','火','a*b','a?b','x y','MON-name_01']
# Exercise the production query builder, including names that need the slow fallback.
script="""$ast=[System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$null)
$fn=$ast.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-SoundMatchQuery'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$names=ConvertFrom-Json $args[1]
@($names | ForEach-Object {Get-SoundMatchQuery $_}) | ConvertTo-Json -Compress
"""
import tempfile
with tempfile.TemporaryDirectory() as tmp:
    f=Path(tmp)/'queries.ps1';f.write_text(script)
    queries=json.loads(subprocess.check_output([a.powershell,'-NoProfile','-File',str(f),str(root/'src/windows.ps1'),json.dumps(names+edge)],text=True))
for name,q in zip(names+edge,queries):
    old=query('from type Sound where name = '+json.dumps(name,ensure_ascii=False));new=query(q)
    assert sorted(x['id'] for x in old)==sorted(x['id'] for x in new),(name,old,new)
assert len(query(queries[10]))==2,'Duplicate fixture must remain ambiguous'
old='from type Sound where '+' or '.join('name = '+json.dumps(n) for n in names)
measure={'scan':[],'search':[]}
for _ in range(5):
    start=time.monotonic();query(old);measure['scan'].append(time.monotonic()-start)
    start=time.monotonic()
    for q in queries[:10]:query(q)
    measure['search'].append(time.monotonic()-start)
print('PASS search matches full scan, including duplicates, case, Unicode, punctuation, missing names and fallback')
print(json.dumps({k:round(statistics.median(v),4) for k,v in measure.items()}))
