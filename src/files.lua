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
function M:command(request,response)
  assert(self.r.GetOS():match('Win'),'File updates require Windows')
  self.seq=self.seq+1
  local token=tostring(self.r.time_precise()):gsub('%D','')..'-'..self.seq
  local ps=self.dir..'/helper-'..C.VERSION..'.ps1'
  local f=assert(io.open(ps,'wb'),'Cannot write the Wwise Relay helper');assert(f:write(self.worker));f:close()
  local path=self.dir..'/request-'..token..'.json'
  f=assert(io.open(path,'wb'));assert(f:write(C.json(request)));f:close()
  local function quoted(s) assert(not s:find('["\r\n]'),'Invalid helper path');return '"'..s:gsub('/','\\')..'"' end
  local root=os.getenv('SystemRoot') or 'C:\\Windows'
  local function literal(s) return "'"..s:gsub("'","''").."'" end
  local script='& ([scriptblock]::Create([IO.File]::ReadAllText('..literal(ps)..'))) -RequestFile '..literal(path)
  if response then script='$result = '..script..'; [IO.File]::WriteAllText('..literal(response)..', [string]$result, [Text.UTF8Encoding]::new($false))' end
  local command=quoted(root..'\\System32\\WindowsPowerShell\\v1.0\\powershell.exe')..' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '..encoded(script)
  return command,path
end
function M:run(request)
  local command,path=self:command(request)
  local output=self.r.ExecProcess(command,60000)
  -- Only our own request file is removed. No WAV backups are made or removed.
  os.remove(path)
  assert(output and output~='','Windows helper did not finish. Update status is uncertain; automatic updates have stopped.')
  local body=output:match('^[^\r\n]*[\r\n]+(.*)$') or ''
  body=body:gsub('^\239\187\191','')
  local ok,data=pcall(C.decode,body)
  assert(ok and type(data)=='table','Windows helper failed. Check PowerShell permissions. '..output:sub(1,350))
  assert(data.ok,data.error or 'Windows file operation failed')
  return data
end
function M:begin_inspect(paths)
  local response=self.dir..'/response-'..tostring(self.r.time_precise()):gsub('%D','')..'.json'
  local command,request=self:command({action='inspect',paths=C.array(paths),hash=false},response)
  self.r.ExecProcess(command,-1)
  return {response=response,request=request,start=self.r.time_precise()}
end
function M:poll(job)
  local f=io.open(job.response,'rb')
  if not f then assert(self.r.time_precise()-job.start<30,'File inspection timed out; updates paused');return nil end
  local raw=f:read('*a');f:close()
  local ok,data=pcall(C.decode,raw)
  if not ok then assert(self.r.time_precise()-job.start<30,'Invalid inspection response');return nil end
  os.remove(job.response);os.remove(job.request)
  assert(data.ok,data.error or 'Inspection failed')
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
