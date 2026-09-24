"""Opt-in integration check against an isolated Wwise 2024.1.1 RelayTest fixture.
Never run in CI or against production audio. On macOS only the launcher and Wine
filesystem paths are adapted; the Lua resolver, WAMP client and file worker are real.
"""
from pathlib import Path
from lupa.lua54 import LuaRuntime
import argparse,base64,hashlib,json,os,re,shutil,subprocess,tempfile,time,uuid
p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);p.add_argument('--powershell',required=True);p.add_argument('--port',type=int,default=8081)
p.add_argument('--matching-only',action='store_true',help='Read-only name matching and large-project request-shape checks')
a=p.parse_args();root=Path(__file__).resolve().parents[1];fixture=a.fixture.resolve()
assert fixture.name=='wwise-live' and (fixture/'RelayTest/RelayTest.wproj').is_file(),'Isolated fixture required'
windows=os.name=='nt';children=[];calls=[]
def native(path):
    if windows:return path
    if path[:2].lower()=='y:':return str(Path.home())+path[2:].replace('\\','/')
    if path[:2].lower()=='z:':return path[2:].replace('\\','/')
    raise AssertionError('Unexpected test filesystem path: '+path)
def win(path):return str(path) if windows else 'Z:'+str(path).replace('/','\\')
def execute(command,timeout):
    assert timeout==-1 and 'wscript.exe" //B //NoLogo' in command
    script=Path(command.rsplit('"',2)[1]).read_text()
    child=json.loads(re.search(r'\.Run\((".*?"), 0, false\)',script).group(1))
    command=command if windows else [a.powershell,'-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',child.rsplit(' -EncodedCommand ',1)[1]]
    children.append(subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW if windows else 0))
    return ''
with tempfile.TemporaryDirectory(prefix='live-',dir=root/'work') as tmp:
    lua=LuaRuntime(unpack_returned_tuples=True);lua.globals().ROOT=str(root)
    for name in ('core','files','wwise'):lua.execute("package.preload['relay.'.. ...]=assert(loadfile(ROOT..'/src/'.. ... ..'.lua'))",name)
    encode=lua.eval("require('relay.core').json");decode=lua.eval("require('relay.core').decode")
    def data(x):return decode(json.dumps(x,ensure_ascii=False))
    r=lua.table_from({'GetResourcePath':lambda:tmp,'RecursiveCreateDirectory':lambda path,flags:Path(path).mkdir(parents=True,exist_ok=True),'GetOS':lambda:'Win64','time_precise':time.monotonic,'genGuid':lambda _: '{'+str(uuid.uuid4())+'}','ExecProcess':execute})
    fs=lua.eval("require('relay.files').new")(r,(root/'src/windows.ps1').read_text())
    # Translate only filesystem requests for the Mac test environment. No production
    # resolver results, protocol responses or safety checks are simulated.
    def map_request(req):
        req=json.loads(encode(req));calls.append(req.copy())
        if not windows:
            for k in ('source','destination','path'):
                if k in req:req[k]=native(req[k])
            if 'paths' in req:req['paths']=[native(x) for x in req['paths']]
        return data(req)
    lua.globals().map_request=map_request
    lua.execute('''local fs=...;local run=fs.run
      function fs:run(req) return run(self,map_request(req)) end''',fs)
    w=lua.eval("require('relay.wwise').new")(r,a.port,fs)
    start=lua.eval('''function(fn,...)
      local args=table.pack(...);local co=coroutine.create(function()return fn(table.unpack(args,1,args.n))end)
      return function()local ok,v=coroutine.resume(co);if not ok then error(v,0)end
        if coroutine.status(co)=='dead' then return true,v end;return false,nil end end''')
    frames=0;worst=0
    def run(fn,*args,limit=150):
        step=start(fn,*args);deadline=time.monotonic()+limit
        global frames,worst
        while time.monotonic()<deadline:
            fs.heartbeat(fs);t=time.monotonic();done,v=step();elapsed=time.monotonic()-t;frames+=1;worst=max(worst,elapsed)
            assert elapsed<.5,elapsed
            if done:return v
            time.sleep(.01)
        raise AssertionError('Live task exceeded deadline')
    lua.globals().w=w;lua.globals().fs=fs
    try:
        project=run(lua.eval('function()local p=w:connect();return p end'))
        assert project['name']=='RelayTest' and native(project['file'])==str(fixture/'RelayTest/RelayTest.wproj'),project['file']
        platform=next(v['id'] for _,v in w['platforms'].items() if v['name']=='Windows')
        profile=data(dict(project_id=project['id'],project_path=project['file'],platform=platform));lua.globals().profile=profile
        print('PASS real Wwise version, project and Windows platform',flush=True)
        originals=Path(native(w['originals']));assert originals.resolve().is_relative_to(fixture/'RelayTest'),'Originals outside fixture'
        import urllib.request
        def identities():
            req=urllib.request.Request('http://127.0.0.1:8090/waapi',data=json.dumps({'uri':'ak.wwise.core.object.get','args':{'from':{'ofType':['AudioFileSource']}},'options':{'return':['id','name','path','parent','originalWavFilePath']}}).encode(),headers={'Content-Type':'application/json'})
            with urllib.request.urlopen(req,timeout=15) as response:return json.load(response)['return']
        source_identities=identities()
        before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in originals.rglob('*.wav')}
        catalog=run(w.catalog,w,profile)
        results={}
        for name in ['Relay_Test_01','Relay_Test_02','Relay_Unmatched','Relay_Duplicate','Relay_Unicode_火','Relay_Shared','Relay_Nested']:
            pair=run(lua.eval('function(path,catalog)local link,why=w:match(path,profile,catalog);return {link=link,why=why}end'),win(fixture/'renders'/(name+'.wav')),catalog)
            results[name]=pair
            print('MATCH',name,'matched' if pair['link'] else pair['why'],flush=True)
        assert results['Relay_Test_01']['link'] and results['Relay_Test_02']['link'] and results['Relay_Unicode_火']['link']
        assert not results['Relay_Unmatched']['link'] and not results['Relay_Duplicate']['link']
        assert not results['Relay_Shared']['link'] and 'shared' in results['Relay_Shared']['why']
        assert results['Relay_Nested']['link']
        assert all(req.get('args',{}).get('from',{}).get('ofType') not in (['Sound'],['AudioFileSource']) for req in calls),'Whole-project audio enumeration'
        print('PASS no whole-project Sound or AudioFileSource response requested',flush=True)
        if not a.matching_only:
            link=results['Relay_Test_01']['link'];lua.globals().link=link
            destination=Path(native(link['original']));unrelated={p:h for p,h in before.items() if Path(p)!=destination}
            converted_hashes={}
            import math,struct,wave
            novel=fixture/'renders-novel';novel.mkdir(exist_ok=True)
            with wave.open(str(novel/'Relay_Test_01.wav'),'wb') as audio:
                audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(48000)
                audio.writeframes(b''.join(struct.pack('<h',round(11000*math.sin(2*math.pi*733*i/48000))) for i in range(48000)))
            metadata=fixture/'renders-metadata';metadata.mkdir(exist_ok=True)
            meta_bytes=bytearray((novel/'Relay_Test_01.wav').read_bytes())+b'JUNK'+struct.pack('<I',4)+b'test'
            struct.pack_into('<I',meta_bytes,4,len(meta_bytes)-8);(metadata/'Relay_Test_01.wav').write_bytes(meta_bytes)
            for take in ('renders','renders-next','renders-next','renders','renders-novel','renders-metadata'):


                link['render']=win(fixture/take/'Relay_Test_01.wav')
                run(w.verify,w,link,profile)
                original=run(fs.inspect,fs,data([link['original']]),True)[1];assert original['ok'],original['error'];link['destination_sha']=original['sha']
                rendered=run(fs.inspect,fs,data([link['render']]),True)[1];assert rendered['ok'],rendered['error']
                previous_hash=run(w.content_hash,w,link,platform)
                replaced=run(fs.replace,fs,link,rendered)
                assert hashlib.sha256(destination.read_bytes()).hexdigest()==rendered['sha']
                if take=='renders-metadata':assert not replaced['audioChanged'],'Metadata was treated as changed sample data'
                run(w.verify,w,link,profile)
                content_hash=run(w.refresh,w,link,profile,previous_hash,replaced['audioChanged'])
                converted=run(w.convert,w,link,platform,content_hash)
                run(fs.artifact,fs,converted,content_hash)
                cache=Path(native(converted)).read_bytes()
                def pcm(b):
                    import struct
                    i=12
                    while i+8<=len(b):
                        k,n=struct.unpack_from('<4sI',b,i)
                        if k==b'data':return b[i+8:i+8+n]
                        i+=8+n+n%2
                    raise AssertionError('No PCM chunk')
                assert pcm(cache)==pcm(Path(native(link['render'])).read_bytes()),'Converted PCM does not match the rendered audio'
                cache_sha=hashlib.sha256(cache).hexdigest()
                if take in converted_hashes:assert converted_hashes[take]==cache_sha,'Identical audio returned different media'
                converted_hashes[take]=cache_sha
                print('PASS replacement + real Wwise conversion + artifact readback',take,converted,flush=True)
            assert len({v for k,v in converted_hashes.items() if k!='renders-metadata'})==3,'Changed audio returned the old converted media'
            assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in unrelated.items())
            print('PASS every unrelated original WAV unchanged',flush=True)
            nested=results['Relay_Nested']['link'];nested['render']=win(fixture/'renders'/'Relay_Test_02.wav')
            # Match name remains Relay_Nested; supply a separate render file of that name.
            nested_render=fixture/'renders'/'Relay_Nested.wav';shutil.copyfile(fixture/'renders'/'Relay_Test_02.wav',nested_render)
            nested['render']=win(nested_render)
            run(w.verify,w,nested,profile)
            baseline=run(w.content_hash,w,nested,platform)
            old=run(fs.inspect,fs,data([nested['original']]),True)[1];nested['destination_sha']=old['sha']
            new=run(fs.inspect,fs,data([nested['render']]),True)[1]
            updated=run(fs.replace,fs,nested,new)
            fresh=run(w.refresh,w,nested,profile,baseline,updated['audioChanged'])
            nested_wem=run(w.convert,w,nested,platform,fresh);run(fs.artifact,fs,nested_wem,fresh)
            assert pcm(Path(native(nested_wem)).read_bytes())==pcm(nested_render.read_bytes())
            assert identities()==source_identities,'Source objects or original paths changed'
            assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in unrelated.items() if Path(p)!=Path(native(nested['original'])))
            print('PASS unrelated WAV hashes also unchanged after nested-source refresh',flush=True)
            assert {str(p) for p in originals.rglob('*.wav')}==set(before),'New original audio was created'
            print('PASS nested original, renamed source, all source IDs/names/parents/paths preserved; no new WAVs',flush=True)
            run(w.show,w,link['container_id'],profile)
            print('PASS Show in Wwise command accepted; inspect UI selection',flush=True)
            print('PASS',frames,'frames, worst frame',round(worst,4),'seconds',flush=True)
    finally:
        fs.close_monitor(fs)
        for child in children:
            try:child.wait(timeout=20)
            except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=5)
        (fixture/'relay-worker-calls.json').write_text(json.dumps(calls,indent=2,ensure_ascii=False))
