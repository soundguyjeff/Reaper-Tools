"""Exercise the actual Lua/background-worker protocol with synthetic WAVs and a
local WAMP test peer. Windows runs the real nonblocking WScript launcher.
No production Wwise instance, game, Dropbox account or user audio is accessed.
"""
from pathlib import Path
from lupa.lua54 import LuaRuntime
import argparse,base64,hashlib,json,os,re,shutil,socket,struct,subprocess,tempfile,threading,time,uuid,wave
parser=argparse.ArgumentParser();parser.add_argument('--powershell');args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1];windows=os.name=='nt'
ps=args.powershell or shutil.which('powershell');assert ps
(ROOT/'work').mkdir(exist_ok=True)
launches=[];children=[]
def execute(command,timeout):
    assert timeout==-1,'REAPER must never wait synchronously on a helper process'
    assert 'wscript.exe" //B //NoLogo' in command,'Never launch a console directly'
    launcher=Path(command.rsplit('"',2)[1]);script=launcher.read_text()
    assert ', 0, false)' in script
    launches.append(command)
    if windows:run=command
    else:
        child=json.loads(re.search(r'\.Run\((".*?"), 0, false\)',script).group(1))
        encoded=child.rsplit(' -EncodedCommand ',1)[1]
        run=[ps,'-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',encoded]
    children.append(subprocess.Popen(run,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NO_WINDOW if windows else 0,close_fds=True))
    return ''
def make_wave(path,seed):
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(48000);f.writeframes(bytes([seed,0])*480)
def wait_for(fn,seconds=20):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        v=fn()
        if v is not None and v is not False:return v
        time.sleep(.01)
    raise AssertionError('Timed out waiting for background helper')
# Minimal test-only WebSocket/WAMP peer; includes fragmented and stalled replies.
def exact(s,n):
    out=b''
    while len(out)<n:
        b=s.recv(n-len(out))
        if not b:raise EOFError()
        out+=b
    return out
def receive(s):
    a,b=exact(s,2);size=b&127
    if size==126:size=struct.unpack('!H',exact(s,2))[0]
    if size==127:size=struct.unpack('!Q',exact(s,8))[0]
    mask=exact(s,4) if b&128 else None;data=exact(s,size)
    if mask:data=bytes(x^mask[i%4] for i,x in enumerate(data))
    if a&15==8:raise EOFError()
    return json.loads(data)
def frame(s,data,opcode=1,final=True):
    n=len(data);head=bytes([(128 if final else 0)|opcode])
    head+=bytes([n]) if n<126 else b'\x7e'+struct.pack('!H',n) if n<65536 else b'\x7f'+struct.pack('!Q',n)
    s.sendall(head+data)
def send(s,value,fragment=False):
    b=json.dumps(value).encode()
    if fragment:
        half=len(b)//2;frame(s,b[:half],final=False);frame(s,b[half:],opcode=0)
    else:frame(s,b)
PROJECT='{11111111-1111-1111-1111-111111111111}'
SOURCE='{22222222-2222-2222-2222-222222222222}'
SOUND='{33333333-3333-3333-3333-333333333333}'
ORIGINAL=r'C:\Game\Originals\SFX\Nested\source.wav'
class Peer:
    def __init__(self,mode):
        self.mode=mode;self.calls=[];self.errors=[];self.stop=threading.Event()
        self.server=socket.socket();self.server.bind(('127.0.0.1',0));self.port=self.server.getsockname()[1];self.server.listen();self.server.settimeout(.2)
        self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()
    def run(self):
        try:
            while not self.stop.is_set():
                try:s,_=self.server.accept()
                except socket.timeout:continue
                with s:
                    s.settimeout(20);header=b''
                    while b'\r\n\r\n' not in header:header+=exact(s,1)
                    key=re.search(br'Sec-WebSocket-Key:\s*([^\r]+)',header,re.I).group(1)
                    accept=base64.b64encode(hashlib.sha1(key+b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
                    s.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\nSec-WebSocket-Protocol: wamp.2.json\r\n\r\n')
                    hello=receive(s);assert hello[0]==1 and hello[1]=='realm1'
                    if self.mode=='handshake_stall':self.stop.wait(17);continue
                    send(s,[2,123,{'roles':{'dealer':{}}}])
                    try:
                        while not self.stop.is_set():
                            req=receive(s);assert req[0]==48 and req[4]==[];self.calls.append(req)
                            if self.mode=='call_stall':self.stop.wait(17);break
                            if self.mode=='error':send(s,[8,48,req[1],{},'ak.test.error',[],{'message':'Synthetic Wwise failure'}]);break
                            if self.mode.startswith('refresh_'):
                                uri=req[3];a=req[5];fields=req[2].get('return',[])
                                if uri=='ak.wwise.core.getProjectInfo':reply={'directories':{'originals':r'C:\Game\Originals'}}
                                elif uri=='ak.wwise.core.audio.import':
                                    assert a=={'autoAddToSourceControl':False,'autoCheckOutToSourceControl':False,'importOperation':'useExisting','default':{'importLanguage':'SFX','importLocation':SOURCE,'originalsSubFolder':'Nested'},'imports':[{'audioFile':ORIGINAL,'objectPath':''}]},a
                                    reply={'files':[ORIGINAL],'objects':[{'id':SOURCE}],'log':[]}
                                    if self.mode=='refresh_error':reply['log']=[{'severity':'Error','message':'Fixture refresh failed'}]
                                    if self.mode=='refresh_wrong_result':reply['objects']=[{'id':SOUND}]
                                elif a.get('from',{}).get('ofType')==['Project']:
                                    reply={'return':[{'id':PROJECT,'filePath':r'C:\Game\game.wproj'}]}
                                    if self.mode=='refresh_wrong_project':reply['return'][0]['id']=SOURCE
                                elif a.get('waql'):
                                    assert a['waql']=='from type AudioFileSource where originalWavFilePath = "'+ORIGINAL+'"'
                                    reply={'return':[{'id':SOURCE}]}
                                    if self.mode=='refresh_shared':reply['return'].append({'id':SOUND})
                                elif fields==['activeSource']:reply={'return':[{'activeSource':{'id':SOURCE}}]}
                                else:
                                    reply={'return':[{'id':SOURCE,'type':'AudioFileSource','parent':{'id':SOUND},'originalWavFilePath':ORIGINAL}]}
                                    if self.mode=='refresh_missing':reply['return']=[]
                                    if self.mode=='refresh_changed_path':reply['return'][0]['originalWavFilePath']=r'C:\Elsewhere\other.wav'
                                send(s,[50,req[1],{},[],reply],True);continue
                            send(s,[50,req[1],{},[],{'version':{'displayName':'2024.1.1 test'},'echo':req[5]}],True)
                    except (EOFError,ConnectionError):pass
        except (OSError,EOFError) as e:
            if not self.stop.is_set():self.errors.append(e)
        except Exception as e:self.errors.append(e)
    def close(self):self.stop.set();self.server.close();self.thread.join(2)

with tempfile.TemporaryDirectory(prefix='bridge-',dir=ROOT/'work') as work:
    directory=Path(work);lua=LuaRuntime(unpack_returned_tuples=True);lua.globals().ROOT=str(ROOT)
    for name in ('core','files','wwise'):lua.execute("package.preload['relay.'.. ...]=assert(loadfile(ROOT..'/src/'.. ... ..'.lua'))",name)
    r=lua.table_from({'GetResourcePath':lambda:str(directory),'RecursiveCreateDirectory':lambda path,flags:Path(path).mkdir(parents=True,exist_ok=True),
        'GetOS':lambda:'Win64','time_precise':time.monotonic,'genGuid':lambda _: '{'+str(uuid.uuid4())+'}','ExecProcess':execute})
    fs=lua.eval("require('relay.files').new")(r,(ROOT/'src/windows.ps1').read_text())
    def request(obj):return lua.eval("require('relay.core').decode")(json.dumps(obj))
    # Resume once per simulated REAPER frame. Measure actual time spent in each frame.
    start=lua.eval('''function(fn,...)
      local args=table.pack(...);local co=coroutine.create(function()return fn(table.unpack(args,1,args.n))end)
      return function()local ok,value=coroutine.resume(co);if not ok then error(value) end
        if coroutine.status(co)=='dead' then return true,value end;return false,nil end
    end''')
    frames=0;worst=0
    def run(fn,*args,limit=40):
        step=start(fn,*args);end=time.monotonic()+limit
        global frames,worst
        while time.monotonic()<end:
            fs.heartbeat(fs);t=time.monotonic();done,value=step();elapsed=time.monotonic()-t;frames+=1;worst=max(worst,elapsed)
            assert elapsed<.5,f'Main-thread step blocked for {elapsed:.3f}s'
            if done:return value
            time.sleep(.01)
        raise AssertionError('Coroutine did not complete')
    audio=directory/"render's $file.wav";make_wave(audio,1)
    unrelated=directory/'unrelated.wav';make_wave(unrelated,9);before=hashlib.sha256(unrelated.read_bytes()).hexdigest()
    paths=lua.table_from([str(audio)])
    try:
        first=run(fs.inspect,fs,paths,False)[1];assert first['ok'];calls=len(launches)
        for seed in range(2,6):
            time.sleep(.04);make_wave(audio,seed);item=run(fs.inspect,fs,paths,False)[1]
            assert item['ok'] and item['stamp']!=first['stamp'];first=item
        assert len(launches)==calls
        print('PASS actual file inspection reuses one hidden worker without blocking frame steps')
        audio.write_bytes(b'bad');bad=run(fs.inspect,fs,paths,False)[1];assert not bad['ok'] and bad['error']
        print('PASS real WAV errors reach Lua')
        for mode in ('normal','error','handshake_stall','call_stall'):
            peer=Peer(mode);before_frames=frames;t=time.monotonic()
            try:
                req=request({'action':'waapi','port':peer.port,'uri':'ak.wwise.core.getInfo','args':{'name':'test $ Unicode 火'},'options':{},'operation':'Read Wwise version'})
                try:
                    result=run(fs.run,fs,req)
                    assert mode=='normal';assert result['data']['echo']['name']=='test $ Unicode 火'
                    assert len(peer.calls)==1
                except Exception as e:
                    assert mode!='normal',str(e)
                    assert ('Synthetic Wwise failure' if mode=='error' else 'timed out') in str(e),str(e)
                    if 'stall' in mode:
                        assert 'Read Wwise version timed out' in str(e),str(e)
                        assert 'This read request does not change audio' in str(e),str(e)
                        assert 'conversion may' not in str(e),str(e)
                        recorded=(Path(fs['dir'])/'last-error.txt').read_text()
                        assert 'Read Wwise version' in recorded and 'timed out' in recorded
                        assert 'Wwise Relay.lua:' not in str(e)
                if 'stall' in mode:
                    assert frames-before_frames>100 and time.monotonic()-t<25
                    print('PASS '+mode+' times out while simulated REAPER frames continue')
                else:print('PASS WAMP '+mode+' response, request fields and fragmented frames')
            finally:peer.close()
            assert not peer.errors,peer.errors
        for mode in ('refresh_ok','refresh_wrong_project','refresh_missing','refresh_changed_path','refresh_shared','refresh_error','refresh_wrong_result'):
            peer=Peer(mode)
            try:
                req=request({'action':'refresh','port':peer.port,'projectId':PROJECT,'projectPath':r'C:\Game\game.wproj',
                    'sourceId':SOURCE,'soundId':SOUND,'original':ORIGINAL,'platform':PROJECT})
                try:
                    result=run(fs.run,fs,req);assert mode=='refresh_ok' and result['ok']
                except Exception as e:
                    assert mode!='refresh_ok',str(e)
                    assert any(word in str(e) for word in ('Wrong Wwise','identity changed','Shared originals','Fixture refresh failed','exact existing')),str(e)
                imports=[c for c in peer.calls if c[3]=='ak.wwise.core.audio.import']
                assert len(imports)==(1 if mode in ('refresh_ok','refresh_error','refresh_wrong_result') else 0)
                print('PASS '+mode+' uses only the exact existing source and nested original')
            finally:peer.close()
            assert not peer.errors,peer.errors
        # Forbidden operations are refused inside the worker, independently of Lua.
        try:run(fs.run,fs,request({'action':'waapi','port':1,'uri':'ak.wwise.core.audio.import','args':{},'options':{}}));raise AssertionError('Import allowed')
        except Exception as e:assert 'not permitted' in str(e)
        assert hashlib.sha256(unrelated.read_bytes()).hexdigest()==before
        print('PASS worker rejects audio import and unrelated audio is unchanged')
        # An expired write request must never commit, even if it reaches the worker.
        make_wave(audio,7);monitor=Path(fs['monitor']['dir'])
        expired={'id':'9999','expires':1,'request':{'action':'replace','source':str(audio),'destination':str(unrelated),'stamp':'old','destinationSha':before}}
        temp=monitor/'expired.tmp';temp.write_text(json.dumps(expired));temp.rename(monitor/'inbox.json')
        response=monitor/'response-9999.json';wait_for(response.exists)
        assert not json.loads(response.read_text())['ok']
        assert hashlib.sha256(unrelated.read_bytes()).hexdigest()==before
        print('PASS expired write request is rejected before changing audio')
        monitor=Path(fs['monitor']['dir']);fs.close_monitor(fs);wait_for(lambda:(monitor/'stopped.json').exists())
        make_wave(audio,8);assert run(fs.inspect,fs,paths,False)[1]['ok'];assert len(launches)==calls+1
        print('PASS stop and restart use a fresh worker session')
        print(f'PASS {frames} simulated REAPER frames; worst actual frame step {worst:.3f}s')
    finally:
        if fs['monitor'] is not None:
            monitor=Path(fs['monitor']['dir']);fs.close_monitor(fs);wait_for(lambda:(monitor/'stopped.json').exists())
        for child in children:child.wait(timeout=5)
print('Real async bridge checks passed'+(' on Windows.' if windows else ' with an adapted macOS launcher.'))
