"""Run the real Lua file bridge against real PowerShell and synthetic WAVs.
Windows CI uses the unmodified Windows command line. A local --powershell path
allows additional testing on macOS/Linux, adapting only the executable/options.
"""
from pathlib import Path
from lupa.lua54 import LuaRuntime
import argparse,base64,hashlib,json,os,re,shutil,subprocess,tempfile,time,uuid,wave

parser=argparse.ArgumentParser()
parser.add_argument('--powershell')
args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
windows=os.name=='nt'
ps=args.powershell or shutil.which('powershell')
assert ps,'Windows PowerShell 5.1 is required, or pass --powershell for a local adapted test.'
(ROOT/'work').mkdir(exist_ok=True)
launches=[]
def execute(command,timeout):
    assert timeout>0,'Regression: negative ExecProcess timeout can open a visible console'
    encoded=command.rsplit(' -EncodedCommand ',1)[1]
    script=base64.b64decode(encoded).decode('utf-16le')
    launches.append(script)
    if '$si.' in script:
        assert '$si.CreateNoWindow=$true' in script and '$si.UseShellExecute=$false' in script
        assert '$si.RedirectStandardOutput=$true' in script, 'Child must not inherit the REAPER capture pipe'
    if windows:
        run=command
    else:
        script=re.sub(r"\$si.FileName='[^']*'",lambda _:"$si.FileName='"+str(ps).replace("'","''")+"'",script)
        script=script.replace(' -WindowStyle Hidden','')
        run=[ps,'-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',base64.b64encode(script.encode('utf-16le')).decode()]
    proc=subprocess.run(run,capture_output=True,timeout=timeout/1000,
        creationflags=subprocess.CREATE_NO_WINDOW if windows else 0)
    return str(proc.returncode)+'\n'+proc.stdout.decode('utf-8-sig',errors='replace')+proc.stderr.decode('utf-8-sig',errors='replace')
def make_wave(path,seed):
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(48000)
        f.writeframes(bytes([seed,0])*480)
def wait_for(fn,seconds=15):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        value=fn()
        if value is not None and value is not False:return value
        time.sleep(.03)
    raise AssertionError('Timed out waiting for background helper')
with tempfile.TemporaryDirectory(prefix='bridge-',dir=ROOT/'work') as work:
    directory=Path(work)
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ROOT=str(ROOT)
    for name in ('core','files'):
        lua.execute("package.preload['relay.'.. ...]=assert(loadfile(ROOT..'/src/'.. ... ..'.lua'))",name)
    r=lua.table_from({
        'GetResourcePath':lambda:str(directory),
        'RecursiveCreateDirectory':lambda path,flags:Path(path).mkdir(parents=True,exist_ok=True),
        'GetOS':lambda:'Win64','time_precise':time.monotonic,
        'genGuid':lambda _: '{'+str(uuid.uuid4())+'}','ExecProcess':execute,
    })
    fs=lua.eval("require('relay.files').new")(r,(ROOT/'src/windows.ps1').read_text(encoding='utf-8'))
    audio=directory/"render's $file.wav";make_wave(audio,1)
    unchanged=directory/'unrelated.wav';make_wave(unchanged,9)
    before=hashlib.sha256(unchanged.read_bytes()).hexdigest()
    paths=lua.table_from([str(audio)])
    try:
        initial=fs.inspect(fs,paths,False)[1]
        assert initial['ok']
        t=time.monotonic();job=fs.begin_inspect(fs,paths)
        assert time.monotonic()-t<8,'Launcher waited for the long-lived child to exit'
        first=wait_for(lambda:fs.poll(fs,job))[1]
        assert first['ok'] and first['stamp']==initial['stamp']
        calls=len(launches)
        for seed in range(2,6):
            time.sleep(.04);make_wave(audio,seed)
            job=fs.begin_inspect(fs,paths);item=wait_for(lambda:fs.poll(fs,job))[1]
            assert item['ok'] and item['stamp']!=first['stamp'];first=item
        assert len(launches)==calls,'Repeated checks launched another PowerShell process'
        print('PASS multiple actual file checks reuse one hidden process and detect same-size rewrites')
        audio.write_bytes(b'bad')
        job=fs.begin_inspect(fs,paths);bad=wait_for(lambda:fs.poll(fs,job))[1]
        assert not bad['ok'] and bad['error'],'Unreadable WAV error was lost'
        print('PASS real WAV inspection errors reach Lua')
        monitor=Path(fs['monitor']['dir']);fs.close_monitor(fs)
        wait_for(lambda:(monitor/'stopped.json').exists())
        make_wave(audio,7);job=fs.begin_inspect(fs,paths)
        assert wait_for(lambda:fs.poll(fs,job))[1]['ok']
        assert len(launches)==calls+1,'Restart should launch exactly one new inspector'
        print('PASS pausing stops the helper, and resuming starts a fresh session')
        monitor=Path(fs['monitor']['dir'])
        bad_request={'id':'9999','paths':[str(audio)],'action':'replace','destination':str(unchanged)}
        temp=monitor/'forbidden.tmp';temp.write_text(json.dumps(bad_request),encoding='utf-8');temp.rename(monitor/'inbox.json')
        wait_for(lambda:(monitor/'stopped.json').exists())
        assert 'Invalid read-only' in json.loads((monitor/'stopped.json').read_text())['error']
        assert hashlib.sha256(unchanged.read_bytes()).hexdigest()==before
        print('PASS persistent inspector rejects mutation requests and leaves unrelated audio unchanged')
    finally:
        if fs['monitor'] is not None:
            monitor=Path(fs['monitor']['dir']);fs.close_monitor(fs)
            wait_for(lambda:(monitor/'stopped.json').exists())
print('Real bridge checks passed'+(' on Windows.' if windows else ' with an adapted non-Windows launcher.'))
