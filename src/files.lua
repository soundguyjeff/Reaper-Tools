local C=require('relay.core')
local M={};M.__index=M
function M.new(r,worker)
  local dir=r.GetResourcePath()..'/Data/WwiseRelay';r.RecursiveCreateDirectory(dir,0)
  return setmetatable({r=r,dir=dir,worker=worker,seq=0},M)
end
local function encoded(s)
  local bytes={}
  for _,cp in utf8.codes(s) do
    if cp>65535 then cp=cp-65536;bytes[#bytes+1]=string.pack('<I2I2',0xd800+(cp>>10),0xdc00+(cp&1023))
    else bytes[#bytes+1]=string.pack('<I2',cp) end
  end
  local data=table.concat(bytes);local out={};local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  for i=1,#data,3 do
    local a,b,c=data:byte(i,i+2);local bits=(a<<16)|((b or 0)<<8)|(c or 0)
    out[#out+1]=alphabet:sub((bits>>18)+1,(bits>>18)+1)..alphabet:sub(((bits>>12)&63)+1,((bits>>12)&63)+1)..(b and alphabet:sub(((bits>>6)&63)+1,((bits>>6)&63)+1) or '=')..(c and alphabet:sub((bits&63)+1,(bits&63)+1) or '=')
  end
  return table.concat(out)
end
M.encoded=encoded
local function literal(s) return "'"..s:gsub("'","''").."'" end
local function exists(path) local f=io.open(path,'rb');if f then f:close();return true end;return false end
local function write(path,data) local f=assert(io.open(path,'wb'));assert(f:write(data));f:close() end
function M:command(request)
  assert(self.r.GetOS():match('Win'),'File updates require Windows')
  self.seq=self.seq+1
  local token=tostring(self.r.time_precise()):gsub('%D','')..'-'..self.seq
  local ps=self.dir..'/helper-'..C.VERSION..'.ps1'
  local f=assert(io.open(ps,'wb'),'Cannot write the Wwise Relay helper');assert(f:write(self.worker));f:close()
  local path=self.dir..'/request-'..token..'.json'
  f=assert(io.open(path,'wb'));assert(f:write(C.json(request)));f:close()
  local function quoted(s) assert(not s:find('["\r\n]'),'Invalid helper path');return '"'..s:gsub('/','\\')..'"' end
  local root=os.getenv('SystemRoot') or 'C:\\Windows'
  local script='& ([scriptblock]::Create([IO.File]::ReadAllText('..literal(ps)..'))) -RequestFile '..literal(path)
  local exe=root..'\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
  local args=' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '..encoded(script)
  return quoted(exe)..args,path,exe,args
end
local function result(output)
  assert(output and output~='','Windows helper did not finish. Update status is uncertain; automatic updates have stopped.')
  local body=output:match('^[^\r\n]*[\r\n]+(.*)$') or ''
  body=body:gsub('^\239\187\191','')
  local ok,data=pcall(C.decode,body)
  assert(ok and type(data)=='table','Windows helper failed. Check PowerShell permissions. '..output:sub(1,350))
  assert(data.ok,data.error or 'Windows file operation failed')
  return data
end
function M:run(request)
  local command,path=self:command(request)
  local output=self.r.ExecProcess(command,60000)
  os.remove(path) -- Only our own JSON request; no WAV backups exist.
  return result(output)
end
function M:close_monitor()
  if not self.monitor then return end
  -- This only stops the read-only inspector; it never interrupts an audio replacement.
  local f=io.open(self.monitor.dir..'/stop','wb');if f then f:write('stop');f:close() end
  self.monitor=nil
end
function M:start_monitor()
  if self.monitor and not exists(self.monitor.dir..'/stopped.json') then return self.monitor end
  self:close_monitor()
  local token=self.r.genGuid(''):gsub('[^%x]','')
  assert(#token==32,'Could not create a file-check session ID')
  local dir=self.dir..'/monitor-'..token
  self.r.RecursiveCreateDirectory(dir,0)
  local _,request,exe,args=self:command({action='monitor',directory=dir})
  -- REAPER captures this short launcher. The inspector must inherit NO handles:
  -- .NET Framework Process.Start can retain the capture pipe until the child exits.
  -- CreateProcessW also suppresses the console at creation, before PowerShell runs.
  local native=[==[
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RelayLauncher {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct StartupInfo {
    public uint cb;
    public string reserved, desktop, title;
    public uint x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
    public ushort showWindow, reservedSize;
    public IntPtr reservedBytes, stdin, stdout, stderr;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct ProcessInfo { public IntPtr process, thread; public uint processId, threadId; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, ExactSpelling=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool CreateProcessW(string application, StringBuilder command,
    IntPtr processAttributes, IntPtr threadAttributes,
    [MarshalAs(UnmanagedType.Bool)] bool inheritHandles, uint flags,
    IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
  [DllImport("kernel32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool CloseHandle(IntPtr handle);
  public static uint Start(string exe, string arguments) {
    StartupInfo si = new StartupInfo(); si.cb = (uint)Marshal.SizeOf(typeof(StartupInfo));
    ProcessInfo pi;
    if (!CreateProcessW(exe, new StringBuilder("\"" + exe + "\"" + arguments),
      IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, null, ref si, out pi))
      throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    try { return pi.processId; }
    finally { CloseHandle(pi.thread); CloseHandle(pi.process); }
  }
}
]==]
  local launch='$ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; try { Add-Type -TypeDefinition '..literal(native)..'; '
    ..'$exe='..literal(exe)..'; $arguments='..literal(args)..'; '
    ..'$childId=[RelayLauncher]::Start($exe,$arguments); @{ok=$true;pid=$childId}|ConvertTo-Json -Compress '
    ..'} catch { @{ok=$false;error=$_.Exception.Message}|ConvertTo-Json -Compress }'
  local command='"'..exe..'" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '..encoded(launch)
  local ok,data=pcall(function() return result(self.r.ExecProcess(command,10000)) end)
  if not ok then write(dir..'/stop','stop');error(data,0) end
  self.monitor={dir=dir,request=request,pid=data.pid}
  return self.monitor
end
function M:begin_inspect(paths)
  local monitor=self:start_monitor()
  self.seq=self.seq+1;local id=tostring(self.seq)
  local request=monitor.dir..'/inbox.json'
  local temporary=monitor.dir..'/inbox.tmp'
  assert(not exists(request),'File inspector already has a pending request')
  write(temporary,C.json({id=id,paths=C.array(paths)}))
  assert(os.rename(temporary,request),'Cannot submit the file inspection')
  return {response=monitor.dir..'/response-'..id..'.json',monitor=monitor,paths=paths,start=self.r.time_precise()}
end
function M:poll(job)
  if exists(job.monitor.dir..'/ready') then os.remove(job.monitor.request) end
  local f=io.open(job.response,'rb')
  if not f then
    local stopped=io.open(job.monitor.dir..'/stopped.json','rb')
    if stopped then
      local raw=stopped:read('*a');stopped:close()
      local ok,data=pcall(C.decode,raw)
      error(ok and data.error or 'File inspector stopped before returning a result',0)
    end
    assert(self.r.time_precise()-job.start<30,'Hidden file inspector did not respond. PowerShell may be blocked; updates paused.')
    return nil
  end
  local raw=f:read('*a');f:close()
  local ok,data=pcall(C.decode,raw)
  assert(ok and type(data)=='table','File inspector returned an invalid response')
  os.remove(job.response)
  assert(data.ok,data.error or 'Inspection failed')
  assert(type(data.items)=='table' and #data.items==#job.paths,'File inspector returned an incomplete file list')
  for i,item in ipairs(data.items) do
    assert(C.key(item.path)==C.key(job.paths[i]),'File inspector returned a different path')
    assert(not item.ok or type(item.stamp)=='string','File inspector returned no file timestamp')
  end
  return data.items
end
function M:inspect(paths,hash)
  if #paths==0 then return {} end
  return self:run({action='inspect',paths=C.array(paths),hash=hash or false}).items
end
function M:replace(link,item)
  return self:run({action='replace',source=link.render,destination=link.original,stamp=item.stamp,destinationSha=link.destination_sha})
end
function M:artifact(path,original_stamp,unchanged)
  local data=self:run({action='artifact',path=path})
  local ticks=tonumber((original_stamp or ''):match('^(%d+):'))
  assert(data.length>0 and (unchanged or (ticks and tonumber(data.ticks)>=ticks)),'Converted media is missing or older than the replaced original')
  return true
end
return M
