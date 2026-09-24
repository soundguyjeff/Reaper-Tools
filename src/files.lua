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
-- All waits happen in a coroutine resumed by the panel once per REAPER frame.
-- WScript is a GUI host: launching it asynchronously creates no terminal window.
local function js_string(value)
  local out={'"'}
  for _,cp in utf8.codes(value) do
    if cp==34 then out[#out+1]='\\"'
    elseif cp==92 then out[#out+1]='\\\\'
    elseif cp<32 or cp>126 then
      if cp>65535 then cp=cp-65536;out[#out+1]=string.format('\\u%04x\\u%04x',0xd800+(cp>>10),0xdc00+(cp&1023))
      else out[#out+1]=string.format('\\u%04x',cp) end
    else out[#out+1]=string.char(cp) end
  end
  out[#out+1]='"';return table.concat(out)
end
function M:trace(message)
  pcall(write,self.dir..'/last-operation.txt',os.date('!%Y-%m-%d %H:%M:%S UTC')..'  '..message..'\n')
end
function M:heartbeat()
  if self.monitor and (not self.heartbeat_time or self.r.time_precise()-self.heartbeat_time>2) then
    write(self.monitor.dir..'/heartbeat','alive');self.heartbeat_time=self.r.time_precise()
  end
end
function M:close_monitor()
  if not self.monitor then return end
  pcall(write,self.monitor.dir..'/stop','stop');self.monitor=nil;self.active=nil
end
function M:start_monitor()
  if self.monitor and not exists(self.monitor.dir..'/stopped.json') then return self.monitor end
  self:close_monitor()
  local token=self.r.genGuid(''):gsub('[^%x]','')
  assert(#token==32,'Could not create a background session ID')
  local dir=self.dir..'/session-'..token
  self.r.RecursiveCreateDirectory(dir,0);write(dir..'/heartbeat','alive')
  local command,request=self:command({action='service',directory=dir})
  local launcher=dir..'/launch.js'
  write(launcher,'try { new ActiveXObject("WScript.Shell").Run('..js_string(command)..', 0, false); } catch(e) { '
    ..'var f=new ActiveXObject("Scripting.FileSystemObject").CreateTextFile('..js_string(dir..'/launcher-error.txt')
    ..',true); f.Write("Windows blocked the background launcher. Check Windows Script Host and PowerShell permissions."); f.Close(); }')
  local exe=(os.getenv('SystemRoot') or 'C:\\Windows')..'\\System32\\wscript.exe'
  -- Never wait on a process in the REAPER/UI thread. No PowerShell process is
  -- directly launched here, and no native ReaWwise call runs in REAPER.
  self.r.ExecProcess('"'..exe..'" //B //NoLogo "'..launcher..'"',-1)
  self.monitor={dir=dir,request=request,start=self.r.time_precise()}
  return self.monitor
end
function M:begin_request(request,timeout)
  local monitor=self:start_monitor()
  assert(not self.active,'Background helper already has a pending request')
  self.seq=self.seq+1;local id=tostring(self.seq)
  local temporary=monitor.dir..'/inbox.tmp'
  local limit=timeout or 35
  write(temporary,C.json({id=id,request=request,expires=os.time()+limit-2}))
  assert(os.rename(temporary,monitor.dir..'/inbox.json'),'Cannot submit background request')
  local job={response=monitor.dir..'/response-'..id..'.json',monitor=monitor,start=self.r.time_precise(),timeout=limit,action=request.action,operation=request.operation or request.uri or request.action,
    may_change_audio=request.action=='replace' or request.action=='refresh' or request.uri=='ak.wwise.core.audio.convert'}
  self.active=job;return job
end
function M:poll_request(job)
  assert(self.monitor==job.monitor,'Background operation stopped; its result may be uncertain. Check the original audio before retrying.')
  if exists(job.monitor.dir..'/ready') then os.remove(job.monitor.request) end
  local f=io.open(job.response,'rb')
  if not f then
    local failed=io.open(job.monitor.dir..'/launcher-error.txt','rb')
    if failed then local message=failed:read('*a');failed:close();error(message,0) end
    local stopped=io.open(job.monitor.dir..'/stopped.json','rb')
    if stopped then local raw=stopped:read('*a');stopped:close();error(C.decode(raw).error or 'Background helper stopped',0) end
    if not exists(job.monitor.dir..'/ready') then
      assert(self.r.time_precise()-job.monitor.start<20,'Background helper did not start. Windows Script Host or PowerShell may be unavailable or blocked. Updates paused.')
    end
    if self.r.time_precise()-job.start>=job.timeout then
      self:close_monitor()
      local detail=job.may_change_audio and 'Audio may already have changed. Check Wwise before retrying.' or 'This request does not change audio.'
      error(job.operation..' timed out. '..detail..' Updates paused.',0)
    end
    return nil
  end
  local raw=f:read('*a');f:close();os.remove(job.response);self.active=nil
  assert(#raw<=33554432,'Background response exceeds 32 MB; updates paused')
  local ok,data=pcall(C.decode,raw)
  assert(ok and type(data)=='table','Background helper returned invalid data')
  if not data.ok then error(data.error or 'Background operation failed',0) end
  return data
end
function M:run(request)
  assert(coroutine.isyieldable(),'Background waits must run outside the UI callback')
  local operation=request.operation or request.uri or request.action
  self:trace(operation..' — started')
  local timeout=(request.action=='replace' or request.uri=='ak.wwise.core.audio.convert') and 130 or 35
  if request.uri=='ak.wwise.core.object.get' and request.args and request.args.waql then timeout=75 end
  if request.action=='refresh' then timeout=210 end
  local job=self:begin_request(request,timeout)
  while true do
    coroutine.yield()
    local ok,data=pcall(self.poll_request,self,job)
    if not ok then
      pcall(write,self.dir..'/last-error.txt',os.date('!%Y-%m-%d %H:%M:%S UTC')..'  '..operation..' — '..tostring(data)..'\n')
      error(data,0)
    end
    if data then self:trace(operation..' — completed');return data end
  end
end
function M:begin_inspect(paths)
  local job=self:begin_request({action='inspect',paths=C.array(paths),hash=false},35);job.paths=paths;return job
end
function M:poll(job)
  local data=self:poll_request(job);if not data then return nil end
  assert(type(data.items)=='table' and #data.items==#job.paths,'Background helper returned an incomplete file list')
  for i,item in ipairs(data.items) do
    assert(C.key(item.path)==C.key(job.paths[i]),'Background helper returned a different path')
    assert(not item.ok or type(item.stamp)=='string','Background helper returned no file timestamp')
  end
  return data.items
end
function M:inspect(paths,hash)
  if #paths==0 then return {} end
  return self:run({action='inspect',paths=C.array(paths),hash=hash or false}).items
end
function M:replace(link,item)
  return self:run({action='replace',source=link.render,destination=link.original,stamp=item.stamp,destinationSha=link.destination_sha,sourcePath=item.resolvedPath,destinationPath=link.destination_path})
end
function M:artifact(path,content_hash)
  assert(C.guid(content_hash),'Wwise returned no content identity')
  local data=self:run({action='artifact',path=path})
  assert(data.length>0 and C.key(data.contentHash)==C.key(content_hash),'Converted media does not match the refreshed Wwise source')
  return true
end
return M
