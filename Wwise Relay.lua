-- @description Wwise Relay - update existing Wwise audio after REAPER/NVK renders
-- @version 0.2.1
-- @author Reaper Tools
-- @about Windows; Wwise 2024.1.1; requires ReaWwise and ReaImGui 0.9.3+.
-- Generated from src/. Single-file install: load this file in REAPER's Actions list.
-- No Wwise objects are created, no audio is imported, no WAV backups are made.

package.preload['relay.core'] = function()
local M = { VERSION = '0.2.1', SECTION = 'WwiseRelay' }

function M.trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
function M.key(p)
  return M.trim(p):gsub('/', '\\'):gsub('\\+$', ''):lower()
end
function M.basename(p) return (p or ''):match('[^/\\]+$') or p end
function M.absolute(p) return type(p)=='string' and (p:match('^%a:[/\\]')~=nil or p:match('^\\\\[^\\]+\\[^\\]+')~=nil) end
function M.guid(s) return type(s)=='string' and s:match('^%{%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x%}$')~=nil end
function M.array(t) return setmetatable(t or {}, {__array=true}) end

-- Strict JSON: profile files are data, never executable Lua.
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return ({['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'})[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end
function M.json(v)
  local t=type(v)
  if t=='string' then return quote(v) end
  if t=='boolean' then return v and 'true' or 'false' end
  if t=='number' then assert(v==v and math.abs(v)~=math.huge,'Non-finite number'); return tostring(v) end
  if t=='nil' then return 'null' end
  assert(t=='table','Unsupported JSON value')
  local out={}
  if (getmetatable(v) or {}).__array or #v>0 then
    for i=1,#v do out[i]=M.json(v[i]) end
    return '['..table.concat(out,',')..']'
  end
  local keys={};for k in pairs(v) do assert(type(k)=='string');keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys) do out[#out+1]=quote(k)..':'..M.json(v[k]) end
  return '{'..table.concat(out,',')..'}'
end
function M.decode(s)
  local i,n,depth=1,#s,0
  local function ws() local _,e=s:find('^%s*',i);i=(e or i-1)+1 end
  local value
  local function str()
    assert(s:sub(i,i)=='"','Expected JSON string');i=i+1;local out={}
    while i<=n do
      local c=s:sub(i,i);i=i+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        local e=s:sub(i,i);i=i+1
        local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if e=='u' then
          local h=s:sub(i,i+3);assert(h:match('^%x%x%x%x$'),'Invalid Unicode escape');i=i+4;local cp=tonumber(h,16)
          if cp>=0xd800 and cp<=0xdbff then
            assert(s:sub(i,i+1)=='\\u','Missing surrogate');i=i+2;local low=tonumber(s:sub(i,i+3),16);i=i+4
            assert(low and low>=0xdc00 and low<=0xdfff,'Invalid surrogate');cp=0x10000+(cp-0xd800)*1024+low-0xdc00
          else assert(cp<0xdc00 or cp>0xdfff,'Invalid surrogate') end
          out[#out+1]=utf8.char(cp)
        else assert(map[e],'Invalid escape');out[#out+1]=map[e] end
      else assert(c:byte()>=32,'Control in string');out[#out+1]=c end
    end
    error('Unclosed string')
  end
  value=function()
    depth=depth+1;assert(depth<64,'JSON too deep');ws();local c=s:sub(i,i);local v
    if c=='"' then v=str()
    elseif c=='{' or c=='[' then
      local array=c=='[';v=array and M.array() or {};i=i+1;ws();local close=array and ']' or '}'
      if s:sub(i,i)~=close then
        repeat
          ws();local k=array and (#v+1) or str();ws()
          if not array then assert(s:sub(i,i)==':','Expected colon');i=i+1 end
          assert(v[k]==nil,'Duplicate JSON key');v[k]=value();ws();c=s:sub(i,i);i=i+1
          if c==close then break end;assert(c==',','Expected comma')
        until false
      else i=i+1 end
    elseif s:sub(i,i+3)=='true' then v=true;i=i+4
    elseif s:sub(i,i+4)=='false' then v=false;i=i+5
    elseif s:sub(i,i+3)=='null' then i=i+4;v=nil
    else
      local num=s:match('^-?%d+%.?%d*[eE]?[+-]?%d*',i);assert(num,'Invalid JSON token');v=tonumber(num);assert(v,'Invalid number');i=i+#num
    end
    depth=depth-1;return v
  end
  local v=value();ws();assert(i>n,'Trailing JSON data');return v
end

-- RENDER_STATS is a completed-render report, not RENDER_TARGETS (a prediction).
-- Semicolons in Windows filenames cannot be disambiguated in this REAPER format.
function M.render_files(stats)
  local files,seen={},{}
  for token in (stats or ''):gmatch('[^;]+') do
    local p=token:match('^FILE:(.+)$')
    if p then
      p=M.trim(p)
      if M.absolute(p) and p:lower():match('%.wav$') and not seen[M.key(p)] then
        files[#files+1]=p;seen[M.key(p)]=true
      end
    end
  end
  return files
end
-- Match a complete filename stem, never a prefix, substring or version-stripped name.
function M.sound_name(path)
  local base=M.basename(path)
  if not M.absolute(path) or not base or not base:lower():match('%.wav$') or path:find(';',1,true) then return nil end
  local name=base:sub(1,-5)
  return name~='' and name or nil
end
function M.match_sound(path,sounds)
  local name=M.sound_name(path)
  if not name then return nil,'Expected a local rendered WAV filename.' end
  local found
  for _,sound in ipairs(sounds) do
    if sound.type=='Sound' and type(sound.name)=='string' and sound.name:lower()==name:lower() then
      if found then return nil,'More than one Wwise Sound is named "'..name..'"; no audio was changed for this file.' end
      found=sound
    end
  end
  if not found then return nil,'No existing Wwise Sound named "'..name..'".' end
  return found
end
-- Reject all competing outputs, so order cannot decide which WAV wins.
function M.reject_collisions(items)
  local owners={}
  for _,item in ipairs(items) do
    if item.link then
      for _,key in ipairs({'sound:'..item.link.sound_id,'original:'..M.key(item.link.original)}) do
        owners[key]=owners[key] or {};owners[key][#owners[key]+1]=item
      end
    end
  end
  for _,group in pairs(owners) do
    if #group>1 then for _,item in ipairs(group) do
      item.skip_reason='Multiple rendered WAVs target the same Wwise sound/original; all competing files were skipped.'
    end end
  end
  for _,item in ipairs(items) do if item.skip_reason then item.link=nil end end
end
function M.validate_link(link,live,all_sources,project_id,project_path)
  assert(M.guid(link.source_id) and M.guid(link.sound_id) and M.guid(link.container_id),'Invalid matched object ID')
  assert(M.absolute(link.render) and M.absolute(link.original),'Absolute file paths required')
  assert(project_id==link.project_id and M.key(project_path)==M.key(link.project_path),'Wrong Wwise project')
  assert(live and live.id==link.source_id and live.type=='AudioFileSource','Matched source is missing or changed')
  assert(live.parent_id==link.sound_id,'Matched source moved to another sound')
  assert(M.key(live.original)==M.key(link.original),'Wwise original path changed during the update; render again')
  assert(live.language=='SFX','Only SFX sources are supported in this release')
  assert(M.key(link.original)~=M.key(link.render),'Render and original paths must differ')
  local count=0
  for _,s in ipairs(all_sources) do if M.key(s.original)==M.key(link.original) then count=count+1;assert(s.id==link.source_id,'Original WAV is shared by another Wwise source') end end
  assert(count==1,'Could not verify exclusive ownership of the original WAV')
  return true
end
function M.conversion_status(errors)
  if type(errors)~='table' then return false,'Wwise returned no conversion result' end
  if #errors==0 then return true,'' end
  local lines={};for _,e in ipairs(errors) do lines[#lines+1]=(e.severity or 'Message')..': '..(e.message or 'Unknown conversion message') end
  -- Warnings are not silently presented as verified success.
  return false,table.concat(lines,'; ')
end

-- After arming, the first signature is a baseline: never replay old renders.
local Detector={};Detector.__index=Detector
function M.detector() return setmetatable({seen={},pending={},ready_at=0},Detector) end
function Detector:baseline(items)
  self.pending={}
  for _,v in ipairs(items) do self.seen[M.key(v.path)]=v.ok and v.stamp or false end
end
function Detector:observe(items,now)
  for _,v in ipairs(items) do
    local k=M.key(v.path)
    if v.ok and self.seen[k]==false then
      self.seen[k]=v.stamp -- Unreadable old report entry: first readable signature is a baseline.
    elseif v.ok and v.stamp~=self.seen[k] then
      self.seen[k]=v.stamp;self.pending[k]=v;self.ready_at=now+2
    end
  end
end
function Detector:take(now)
  if now<self.ready_at then return nil end
  local out={};for _,v in pairs(self.pending) do out[#out+1]=v end
  self.pending={};table.sort(out,function(a,b)return a.path<b.path end)
  return #out>0 and out or nil
end
function Detector:cancel() self.pending={} end
M.Detector=Detector
return M

end

package.preload['relay.wwise'] = function()
local C=require('relay.core')
local M={};M.__index=M
local allow={
 ['ak.wwise.core.object.get']=true,['ak.wwise.core.getInfo']=true,
 ['ak.wwise.core.getProjectInfo']=true,
 ['ak.wwise.core.audio.convert']=true,['ak.wwise.ui.commands.execute']=true,
 ['ak.wwise.ui.bringToForeground']=true,
}
function M.new(r,port) return setmetatable({r=r,port=port or 8080,connected=false},M) end
function M:call(uri,args,options,read)
  assert(allow[uri],'Wwise operation is not permitted')
  if uri=='ak.wwise.ui.commands.execute' then assert(args.command=='FindInProjectExplorerSyncGroup1','Only navigation is permitted') end
  if uri=='ak.wwise.core.audio.convert' then
    assert(#args.objects==1 and C.guid(args.objects[1]),'Conversion must target one matched audio source')
    assert(#args.platforms==1 and #args.languages==1 and args.languages[1]=='SFX','Conversion scope is invalid')
  end
  local r,owned=self.r,{}
  local function own(p) if p then owned[#owned+1]=p end;return p end
  local function encode(v)
    if type(v)=='string' then return own(r.AK_AkVariant_String(v)) end
    if type(v)=='boolean' then return own(r.AK_AkVariant_Bool(v)) end
    if type(v)=='number' then return own(r.AK_AkVariant_Int(v)) end
    assert(type(v)=='table')
    local arr=(getmetatable(v) or {}).__array or #v>0
    local p=own(arr and r.AK_AkJson_Array() or r.AK_AkJson_Map())
    if arr then for _,x in ipairs(v) do assert(r.AK_AkJson_Array_Add(p,encode(x))) end
    else for k,x in pairs(v) do assert(r.AK_AkJson_Map_Set(p,k,encode(x))) end end
    return p
  end
  local Q={}
  function Q.get(p,k) return own(r.AK_AkJson_Map_Get(p,k)) end
  function Q.text(p,k) local v=k and Q.get(p,k) or p;return v and r.AK_AkVariant_GetString(v) or '' end
  function Q.list(p,k,reader)
    local a=k and Q.get(p,k) or p;local out={};if not a then return out end
    for i=0,r.AK_AkJson_Array_Size(a)-1 do out[#out+1]=reader(own(r.AK_AkJson_Array_Get(a,i))) end
    return out
  end
  local ok,result=pcall(function()
    local p=own(r.AK_Waapi_Call(uri,encode(args or {}),encode(options or {})))
    assert(p,'Wwise did not respond')
    assert(r.AK_AkJson_GetStatus(p),Q.text(p,'message')~='' and Q.text(p,'message') or ('Wwise rejected '..uri))
    return read and read(Q,p) or true
  end)
  -- Clear only handles created by this call; ReaWwise is shared with other tools.
  for i=#owned,1,-1 do pcall(r.AK_AkJson_Clear,owned[i]) end
  if not ok then error(result,0) end
  return result
end
local function read_object(Q,p)
  local par=Q.get(p,'parent')
  return {id=Q.text(p,'id'),name=Q.text(p,'name'),type=Q.text(p,'type'),path=Q.text(p,'path'),
    original=Q.text(p,'originalWavFilePath'),file=Q.text(p,'filePath'),
    converted=Q.text(p,'convertedWemFilePath'),parent_id=par and Q.text(par,'id') or ''}
end
local fields={'id','name','type','path','parent','filePath','originalWavFilePath'}
function M:objects(from,extra)
  local opt={['return']=fields};if extra then opt=extra end
  return self:call('ak.wwise.core.object.get',{from=from},opt,function(Q,p)return Q.list(p,'return',function(x)return read_object(Q,x)end)end)
end
function M:object(id,extra)
  assert(C.guid(id),'Invalid Wwise object ID')
  local a=self:objects({id={id}},extra);assert(#a==1,'Wwise object is missing');return a[1]
end
function M:project()
  local p=self:objects({ofType={'Project'}},{['return']={'id','name','filePath'}})
  assert(#p==1 and C.guid(p[1].id) and C.absolute(p[1].file),'Could not identify the open Wwise project')
  return p[1]
end
function M:connect()
  assert(self.r.AK_Waapi_Connect,'Install Audiokinetic ReaWwise through ReaPack, then restart REAPER')
  assert(self.r.AK_Waapi_Connect('127.0.0.1',self.port),'Cannot connect. Enable WAAPI in Wwise preferences and check the port.')
  local version=self:call('ak.wwise.core.getInfo',{}, {},function(Q,p)return Q.text(Q.get(p,'version'),'displayName')end)
  assert(version:match('2024%.1%.1%f[^%d]'),'This release targets the Wwise 2024.1.1 API. Connected version: '..version)
  local project=self:project()
  local info=self:call('ak.wwise.core.getProjectInfo',{}, {},function(Q,p)
    return {originals=Q.text(Q.get(p,'directories'),'originals'),platforms=Q.list(p,'platforms',function(v)return {id=Q.text(v,'id'),name=Q.text(v,'name')} end)}
  end)
  assert(C.absolute(info.originals),'Wwise did not return an absolute Originals directory')
  if #info.platforms==0 then
    info.platforms=self:objects({ofType={'Platform'}},{['return']={'id','name'}})
  end
  assert(#info.platforms>0,'Wwise returned no conversion platforms')
  self.connected=true;self.originals=info.originals;self.platforms=info.platforms;self.version=version
  return project,info
end
function M:sources()
  local a=self:objects({ofType={'AudioFileSource'}})
  local prefix=C.key(self.originals)..'\\sfx\\'
  for _,s in ipairs(a) do s.language=C.key(s.original):sub(1,#prefix)==prefix and 'SFX' or 'Other' end
  return a
end
function M:check_project(profile)
  local p=self:project()
  assert(p.id==profile.project_id and C.key(p.file)==C.key(profile.project_path),'Wrong Wwise project; updates paused')
  local platforms=self:objects({ofType={'Platform'}},{['return']={'id','name'}})
  local valid=false;for _,v in ipairs(platforms) do if v.id==profile.platform then valid=true end end
  assert(valid,'Pinned conversion platform is missing')
  return p
end
function M:catalog(profile)
  self:check_project(profile)
  return {sounds=self:objects({ofType={'Sound'}},{['return']={'id','name','type','path','parent'}}),sources=self:sources()}
end
function M:active_source(sound_id,platform)
  return self:call('ak.wwise.core.object.get',{from={id={sound_id}}},{['return']={'activeSource'},platform=platform},function(Q,p)
    return Q.list(p,'return',function(x)return Q.text(Q.get(x,'activeSource'),'id')end)[1]
  end)
end
function M:match(path,profile,catalog)
  local sound,reason=C.match_sound(path,catalog.sounds)
  if not sound then return nil,reason end
  local active=self:active_source(sound.id,profile.platform)
  local source
  for _,candidate in ipairs(catalog.sources) do if candidate.id==active then source=candidate end end
  if not source then return nil,'The matched sound has no active file-based audio source on the selected platform.' end
  local link={render=path,source_id=source.id,sound_id=sound.id,container_id=sound.parent_id,
    sound_name=sound.name,sound_path=sound.path,source_path=source.path,original=source.original,
    project_id=profile.project_id,project_path=profile.project_path}
  local ok,err=pcall(C.validate_link,link,source,catalog.sources,profile.project_id,profile.project_path)
  if not ok then return nil,tostring(err) end
  local container=self:object(sound.parent_id)
  link.container_path=container.path
  return link
end
function M:verify(link,profile)
  local catalog=self:catalog(profile)
  local sound,reason=C.match_sound(link.render,catalog.sounds)
  assert(sound,reason)
  assert(sound.id==link.sound_id,'The matching Wwise sound changed during the update')
  assert(sound.parent_id==link.container_id,'Sound moved to another container during the update; render again')
  local live
  for _,s in ipairs(catalog.sources) do if s.id==link.source_id then live=s end end
  C.validate_link(link,live,catalog.sources,profile.project_id,profile.project_path)
  assert(self:active_source(sound.id,profile.platform)==link.source_id,'Active Wwise source changed; update skipped')
  return true
end
function M:convert(link,platform)
  local errors=self:call('ak.wwise.core.audio.convert',{objects={link.source_id},platforms={platform},languages={'SFX'}},{},function(Q,p)
    local a=Q.get(p,'errors');assert(a,'Wwise returned no conversion report')
    return Q.list(a,nil,function(x)return {severity=Q.text(x,'severity'),message=Q.text(x,'message')}end)
  end)
  local ok,message=C.conversion_status(errors);assert(ok,message)
  local source=self:object(link.source_id,{['return']={'id','convertedWemFilePath'},platform=platform})
  assert(source.converted~='','Wwise did not return the converted file location')
  return source.converted
end
function M:show(container_id,profile)
  local p=self:project();assert(p.id==profile.project_id and C.key(p.file)==C.key(profile.project_path),'The pinned Wwise project is not open')
  self:object(container_id)
  self:call('ak.wwise.ui.commands.execute',{command='FindInProjectExplorerSyncGroup1',objects={container_id}})
  local ok=pcall(function()self:call('ak.wwise.ui.bringToForeground',{})end)
  return ok
end
return M

end

package.preload['relay.files'] = function()
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
  -- REAPER's negative ExecProcess timeout may create a visible terminal before
  -- PowerShell can hide itself. Launch once through its captured, synchronous path;
  -- .NET creates the long-lived read-only child without a console in the first place.
  local launch='$ErrorActionPreference="Stop"; try { '
    ..'$si=[Diagnostics.ProcessStartInfo]::new(); $si.FileName='..literal(exe)..'; $si.Arguments='..literal(args)..'; '
    ..'$si.UseShellExecute=$false; $si.CreateNoWindow=$true; $si.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden; '
    ..'$si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true; '
    ..'$child=[Diagnostics.Process]::Start($si); @{ok=$true;pid=$child.Id}|ConvertTo-Json -Compress; $child.Dispose() '
    ..'} catch { @{ok=$false;error=$_.Exception.Message}|ConvertTo-Json -Compress }'
  local command='"'..exe..'" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '..encoded(launch)
  local ok,data=pcall(result,self.r.ExecProcess(command,10000))
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

end

package.preload['relay.worker'] = function() return [====[
param([Parameter(Mandatory=$true)][string]$RequestFile)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
function SafePath([string]$p) {
  if (![System.IO.Path]::IsPathRooted($p) -or $p.StartsWith('\\') -or $p.StartsWith('\\?\')) { throw 'Only local absolute Windows paths are supported.' }
  if ($p.Contains(';') -or $p.Substring(2).Contains(':')) { throw 'Semicolons and alternate data streams are not supported.' }
  $full=[IO.Path]::GetFullPath($p)
  $item=Get-Item -LiteralPath $full -Force
  if ($item.PSIsContainer) { throw 'Expected an existing file.' }
  $part=$item
  while ($null -ne $part) {
    if (($part.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Symlinks and junctions are not supported.' }
    $part=$part.Parent
    if ($null -eq $part -and $item -is [IO.FileInfo]) { $part=$item.Directory;$item=$part }
  }
  return $full
}
function HashStream($s) {
  $s.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant() }
  finally { $sha.Dispose();$s.Position=0 }
}
function WaveInfo($s) {
  # Conservative first release: standard RIFF WAV, PCM/IEEE float/extensible.
  # Reject incomplete files, RF64/BW64 and malformed chunk sizes instead of guessing.
  $s.Position=0;$r=[IO.BinaryReader]::new($s,[Text.Encoding]::ASCII,$true)
  try {
    if ($s.Length -lt 44) { throw 'WAV is empty or incomplete.' }
    $riff=[Text.Encoding]::ASCII.GetString($r.ReadBytes(4));$size=$r.ReadUInt32();$wave=[Text.Encoding]::ASCII.GetString($r.ReadBytes(4))
    if ($riff -ne 'RIFF' -or $wave -ne 'WAVE') { throw 'Expected a standard RIFF WAV (RF64/BW64 not yet supported).' }
    if ([int64]$size+8 -ne $s.Length) { throw 'WAV size does not match its header; render may be incomplete.' }
    $fmt=$false;$data=$false;$channels=0;$rate=0;$align=0;$bytes=0
    while ($s.Position+8 -le $s.Length) {
      $id=[Text.Encoding]::ASCII.GetString($r.ReadBytes(4));$length=$r.ReadUInt32();$end=$s.Position+[int64]$length
      if ($end -gt $s.Length) { throw 'WAV contains an incomplete chunk.' }
      if ($id -eq 'fmt ') {
        if ($length -lt 16) { throw 'WAV format chunk is incomplete.' }
        $tag=$r.ReadUInt16();$channels=$r.ReadUInt16();$rate=$r.ReadUInt32();$null=$r.ReadUInt32();$align=$r.ReadUInt16();$bits=$r.ReadUInt16()
        if ($tag -notin @(1,3,65534) -or $channels -lt 1 -or $channels -gt 64 -or $rate -lt 8000 -or $align -lt 1) { throw 'Unsupported WAV format.' }
        $fmt=$true
      }
      if ($id -eq 'data') { $bytes=$length;$data=$length -gt 0 }
      $s.Position=$end+($length % 2)
    }
    if (!$fmt -or !$data -or ($bytes % $align) -ne 0) { throw 'WAV contains no complete audio frames.' }
    return @{channels=$channels;rate=$rate}
  } finally { $r.Dispose();$s.Position=0 }
}
function Inspect([string]$p,[bool]$hash=$false) {
  try {
    $full=SafePath $p;$f=Get-Item -LiteralPath $full
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
      $info=WaveInfo $stream
      $result=@{path=$p;ok=$true;stamp=([string]$f.LastWriteTimeUtc.Ticks+':'+[string]$f.Length);length=$f.Length;channels=$info.channels;rate=$info.rate}
      if ($hash) { $result.sha=HashStream $stream }
      return $result
    } finally { $stream.Dispose() }
  } catch { return @{path=$p;ok=$false;error=$_.Exception.Message} }
}
function Monitor([string]$directory) {
  $dir=[IO.Path]::GetFullPath($directory)
  if (!(Test-Path -LiteralPath $dir -PathType Container)) { throw 'Missing file-check session directory.' }
  $inbox=Join-Path $dir 'inbox.json';$stop=Join-Path $dir 'stop'
  $reason='File inspector stopped after being idle; a new session will start on the next check.'
  try {
    [IO.File]::WriteAllText((Join-Path $dir 'ready'),'ready')
    $idle=[DateTime]::UtcNow
    while (!(Test-Path -LiteralPath $stop) -and ([DateTime]::UtcNow-$idle).TotalSeconds -lt 30) {
      if (Test-Path -LiteralPath $inbox) {
        $message=[IO.File]::ReadAllText($inbox,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([string]$message.id -notmatch '^[0-9]+$' -or !$message.paths -or $message.action) { throw 'Invalid read-only inspection request.' }
        [IO.File]::Delete($inbox)
        # Only inspect is available in the persistent worker. It cannot replace audio.
        $items=@(foreach ($path in $message.paths) { Inspect $path $false })
        $json=@{ok=$true;items=$items} | ConvertTo-Json -Depth 8 -Compress
        $temp=Join-Path $dir ('response-'+$message.id+'.tmp')
        $dest=Join-Path $dir ('response-'+$message.id+'.json')
        [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temp,$dest) # Publish a complete, unique response atomically.
        $idle=[DateTime]::UtcNow
      }
      Start-Sleep -Milliseconds 100
    }
  } catch { $reason=$_.Exception.Message }
  finally {
    $json=@{error=$reason} | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $dir 'stopped.json'),$json,[Text.UTF8Encoding]::new($false))
  }
}

try {
  $req=Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($req.action -eq 'monitor') {
    Monitor $req.directory
  } elseif ($req.action -eq 'inspect') {
    $items=@(foreach ($p in $req.paths) { Inspect $p ([bool]$req.hash) })
    @{ok=$true;items=$items} | ConvertTo-Json -Depth 8 -Compress
  } elseif ($req.action -eq 'artifact') {
    $p=SafePath $req.path;$f=Get-Item -LiteralPath $p
    @{ok=$true;length=$f.Length;ticks=[string]$f.LastWriteTimeUtc.Ticks} | ConvertTo-Json -Compress
  } elseif ($req.action -eq 'replace') {
    $src=SafePath $req.source;$dst=SafePath $req.destination
    if ([StringComparer]::OrdinalIgnoreCase.Equals($src,$dst)) { throw 'Source and destination must differ.' }
    if (([IO.File]::GetAttributes($dst) -band [IO.FileAttributes]::ReadOnly) -ne 0) { throw 'Original WAV is read-only; check it out in source control first.' }
    $renderStream=$null;$original=$null;$out=$null;$temp=$null
    try {
      # No writer may change the render while it is validated and copied.
      $renderStream=[IO.File]::Open($src,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $si=Get-Item -LiteralPath $src
      if (([string]$si.LastWriteTimeUtc.Ticks+':'+[string]$si.Length) -ne $req.stamp) { throw 'Render changed after it was queued.' }
      $wi=WaveInfo $renderStream;$sha=HashStream $renderStream
      $original=[IO.File]::Open($dst,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $old=WaveInfo $original
      if ($old.channels -ne $wi.channels) { throw 'Channel count changed; update skipped.' }
      if ((HashStream $original) -ne $req.destinationSha) { throw 'Wwise original changed while preparing this update; render again after the other edit finishes.' }
      $original.Dispose();$original=$null
      $temp=Join-Path ([IO.Path]::GetDirectoryName($dst)) ('.wwise-relay-'+[guid]::NewGuid().ToString('N')+'.tmp')
      $out=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
      $renderStream.CopyTo($out);$out.Flush($true)
      if ((HashStream $out) -ne $sha) { throw 'Staged audio failed verification.' }
      $out.Dispose();$out=$null
      # Recheck immediately before the atomic, no-backup replacement.
      $original=[IO.File]::Open($dst,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      if ((HashStream $original) -ne $req.destinationSha) { throw 'Original changed during replacement preparation.' }
      $original.Dispose();$original=$null
      [IO.File]::Replace($temp,$dst,[System.Management.Automation.Language.NullString]::Value);$temp=$null
      $verify=Inspect $dst $true
      if (!$verify.ok -or $verify.sha -ne $sha) { throw 'Replacement occurred, but readback verification failed. Check the original WAV.' }
      @{ok=$true;sha=$sha;stamp=$verify.stamp;channels=$wi.channels;rate=$wi.rate} | ConvertTo-Json -Compress
    } finally {
      if ($null -ne $renderStream) {$renderStream.Dispose()};if ($null -ne $original) {$original.Dispose()};if ($null -ne $out) {$out.Dispose()}
      if ($null -ne $temp -and [IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
  } else { throw 'Unknown helper operation.' }
} catch { @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Compress }
]====] end

local C=require('relay.core')
local W=require('relay.wwise')
local F=require('relay.files')
local worker=require('relay.worker')
local r=reaper
assert(r,'Load this script through REAPER Actions > New action > Load ReaScript')
if not r.ImGui_GetBuiltinPath then r.MB('Install ReaImGui through ReaPack, then restart REAPER.','Wwise Relay',0);return end
package.path=r.ImGui_GetBuiltinPath()..'/?.lua;'..package.path
local I=require('imgui')('0.9.3')
local ctx=I.CreateContext('Wwise Relay')
local win=r.GetOS():match('Win')~=nil
local proj=r.EnumProjects(-1)
-- REAPER has no native GetProjectGUID. The master track provides a persistent
-- project-local identity using built-in APIs, without requiring SWS.
local function project_identity(project)
  local master=r.GetMasterTrack(project)
  local guid=master and r.GetTrackGUID(master)
  return C.guid(guid) and guid or nil
end
local project_guid=project_identity(proj)
if not project_guid then
  r.MB('Could not identify the active REAPER project. Open a project and run Wwise Relay again.','Wwise Relay',0)
  return
end
local key='profile:'..project_guid
local profile={version=2,port=8080,platform='',notify=true}
local saved=r.GetExtState(C.SECTION,key)
local startup_error
if saved~='' then
  local ok,p=pcall(C.decode,saved)
  if ok and type(p)=='table' and (p.version==1 or p.version==2) and type(p.port)=='number' and type(p.platform)=='string' then
    -- Preserve project/platform preferences, but never reuse old manual audio links.
    p.links=nil;p.version=2;profile=p
  else startup_error='Saved profile could not be loaded. Set up the project again.' end
end
local w=W.new(r,profile.port)
local fs=F.new(r,worker)
local s={enabled=false,status='Ready to set up',detail='Connect to Wwise and choose your project and platform.',error=startup_error,
  results={},containers={},details=false,detector=C.detector(),job=nil,next_probe=0,last_stats='',pending={},busy=false,
  tab='Setup',toast='',toast_until=0,selected_container=1,last_files={}}
local heartbeat_key='instance:'..project_guid
local now=r.time_precise()
local prior=tonumber(r.GetExtState(C.SECTION,heartbeat_key)) or 0
if prior>0 and math.abs(now-prior)<4 then r.MB('Wwise Relay is already running for this REAPER project.','Wwise Relay',0);return end
r.SetExtState(C.SECTION,heartbeat_key,tostring(now),false)
local function save() r.SetExtState(C.SECTION,key,C.json(profile),true) end
local function toast(text) s.toast=text;s.toast_until=r.time_precise()+6 end
local function pause(message)
  fs:close_monitor()
  s.enabled=false;s.detector:cancel();s.pending={};s.busy=false;s.error=tostring(message);s.toast='';s.status='Updates paused';s.detail='Resolve the issue, then enable updates again.'
end
local function guard(fn)
  local ok,err=pcall(fn)
  if not ok then pause(err) end
  return ok
end
local function current_project()
  assert(r.EnumProjects(-1)==proj and project_identity(proj)==project_guid,'Active REAPER project changed. Return to the original project and re-enable updates.')
end
local function stats()
  local ok,value=r.GetSetProjectInfo_String(proj,'RENDER_STATS','',false)
  return ok and value or ''
end
local function matched_project(p)
  return profile.project_id==p.id and C.key(profile.project_path)==C.key(p.file)
end
local function connect()
  assert(win,'This is a Windows tool. The panel can be previewed on this Mac, but live updates are disabled.')
  w.port=profile.port
  local p,info=w:connect()
  if profile.project_id then assert(matched_project(p),'Open the pinned project in Wwise: '..profile.project_path) end
  s.connected_project=p;s.error=nil;s.status='Connected';s.detail='Ready to match rendered filenames to existing Wwise sounds.'
  s.info=info
end
local function pin()
  assert(s.connected_project,'Connect to Wwise first')
  current_project()
  assert(not profile.project_id or matched_project(s.connected_project),'The pinned Wwise project must remain open')
  profile.project_id=s.connected_project.id;profile.project_path=s.connected_project.file;profile.project_name=s.connected_project.name
  if profile.platform=='' then
    for _,p in ipairs(w.platforms) do if p.name=='Windows' then profile.platform=p.id end end
    if profile.platform=='' then profile.platform=w.platforms[1].id end
  end
  save();toast('Project pinned. Enable updates and render as usual.')
end
local function platform_name()
  for _,p in ipairs(w.platforms or {}) do if p.id==profile.platform then return p.name end end
  return profile.platform_name or 'Choose platform'
end
local function enable()
  fs:close_monitor();s.inspect_failure=nil
  current_project();assert(win,'Live updates require Windows');assert(w.connected,'Connect to Wwise first')
  assert(profile.project_id,'Connect and choose Use this project in Setup first')
  assert(matched_project(w:project()),'Wrong Wwise project')
  local valid=false;for _,p in ipairs(w.platforms) do if p.id==profile.platform then valid=true end end
  assert(valid,'Select a valid conversion platform')
  s.detector=C.detector()
  s.last_stats=stats();s.last_files=C.render_files(s.last_stats)
  -- Baseline only paths in the old completed report. No manual links or folder watch.
  if #s.last_files>0 then s.detector:baseline(fs:inspect(s.last_files)) end
  s.pending={};s.job=nil;s.enabled=true;s.error=nil;s.status='Waiting for render';s.detail='Render through NVK as usual.';s.next_probe=r.time_precise()+1.5;save()
end
local function summary()
  local good,skipped,failed=0,0,0
  for _,v in ipairs(s.results) do
    if v.state=='Converted' then good=good+1 elseif v.state=='Skipped' then skipped=skipped+1 else failed=failed+1 end
  end
  s.status=failed+skipped==0 and 'Wwise audio updated' or 'Some audio needs attention'
  s.detail=string.format('%d replaced + converted  |  %d skipped  |  %d failed',good,skipped,failed)
  if failed>0 then s.enabled=false;s.detail=s.detail..' — updates paused' end
  if good>0 and failed+skipped==0 and profile.notify then toast('Wwise confirmed: '..good..' WAVs replaced and converted') end
end
local function begin_batch(items)
  current_project()
  local catalog=w:catalog(profile)
  for _,item in ipairs(items) do item.link,item.skip_reason=w:match(item.path,profile,catalog) end
  C.reject_collisions(items)
  s.tab='Latest render';s.results={};s.containers={};s.selected_container=1;s.pending=items;s.busy=true;s.error=nil;s.toast=''
end
local function process_one()
  local item=table.remove(s.pending,1);if not item then return end
  current_project()
  local link=item.link
  local row={path=item.path,state='Skipped',message=item.skip_reason or 'No unambiguous existing sound matched.'};s.results[#s.results+1]=row
  if link then
    row.link=link;row.state='Failed';s.status='Updating '..C.basename(item.path);s.detail='Verifying the existing source...'
    local ok,err=pcall(function()
      w:verify(link,profile)
      local checks=fs:inspect({link.original},true)
      local original=checks[1]
      assert(original and original.ok,original and original.error or 'Cannot read the matched original WAV')
      link.destination_sha=original.sha
      local previous_sha=link.destination_sha
      local replaced=fs:replace(link,item)
      row.replaced=true;row.state='Conversion failed';link.destination_sha=replaced.sha
      -- Verify identity again after replacement; never convert a new/moved object.
      w:verify(link,profile)
      local converted=w:convert(link,profile.platform)
      fs:artifact(converted,replaced.stamp,previous_sha==replaced.sha)
      row.state='Converted';row.message='Original bytes verified; Wwise reported no conversion messages; converted media is current.'
      local have=false;for _,v in ipairs(s.containers) do if v.id==link.container_id then have=true end end
      if not have then s.containers[#s.containers+1]={id=link.container_id,path=link.container_path} end
    end)
    if not ok then
      row.message=tostring(err);s.error=row.message;s.enabled=false
      for _,remaining in ipairs(s.pending) do
        s.results[#s.results+1]={path=remaining.path,state='Not processed',message='Paused after the preceding failure.',link=remaining.link}
      end
      s.pending={}
    end
  end
  if #s.pending==0 then s.busy=false;summary() end
end
local function retry_failed()
  current_project();assert(w.connected,'Connect first')
  local paths={};for _,v in ipairs(s.results) do if v.state~='Converted' then paths[#paths+1]=v.path end end
  assert(#paths>0,'No skipped or failed files to retry')
  local items=fs:inspect(paths)
  for _,v in ipairs(items) do assert(v.ok,v.error or 'Cannot read rendered file') end
  begin_batch(items)
end
local function tick()
  local time=r.time_precise();r.SetExtState(C.SECTION,heartbeat_key,tostring(time),false)
  if s.busy then process_one();return end
  if not s.enabled then return end
  current_project()
  local report=stats()
  if report=='' then s.detector:cancel();s.last_stats='';s.last_files={};s.job=nil;s.inspect_failure=nil;fs:close_monitor();return end
  local files=C.render_files(report)
  if #files==0 then return end
  if s.job then
    local items=fs:poll(s.job)
    if items then
      -- A cancelled or replaced render report invalidates an in-flight inspection.
      if report==s.job.report then
        local failures={}
        for _,item in ipairs(items) do if not item.ok then failures[#failures+1]=item end end
        if #failures>0 then
          if not s.inspect_failure or s.inspect_failure.report~=report then s.inspect_failure={report=report,since=time} end
          s.status='Checking rendered WAVs';s.detail='Waiting for readable, complete files: '..C.basename(failures[1].path)
          if time-s.inspect_failure.since>=8 then
            s.results={};s.containers={};s.tab='Latest render';s.details=true
            for _,item in ipairs(items) do s.results[#s.results+1]={path=item.path,state=item.ok and 'Not processed' or 'File check failed',
              message=item.ok and 'Another rendered file could not be read.' or (item.error or 'Cannot inspect WAV')} end
            pause(failures[1].path..': '..(failures[1].error or 'Cannot inspect WAV'));s.job=nil;return
          end
        else
          s.inspect_failure=nil;s.detector:observe(items,time)
          if s.status=='Checking rendered WAVs' then s.status='Waiting for render';s.detail='Render through NVK as usual.' end
        end
      end
      s.job=nil
    end
  end
  if not s.job and time>=s.next_probe then
    s.job=fs:begin_inspect(files);s.job.report=report;s.next_probe=time+1.5;s.last_stats=report;s.last_files=files
  end
  if s.inspect_failure then return end
  local ready=s.detector:take(time)
  if ready then begin_batch(ready) end
end

local green,amber,red,muted=0x95D5AEFF,0xEDC28AFF,0xEBA0A0FF,0xB0B5BEFF
local function text(s) I.TextWrapped(ctx,tostring(s or '')) end
local function button(label,fn,disabled)
  I.BeginDisabled(ctx,disabled or false)
  if I.Button(ctx,label) then guard(fn) end
  I.EndDisabled(ctx)
end
local function render_tab()
  local color=(s.error or s.status=='Some audio needs attention') and amber or green
  I.TextColored(ctx,color,s.status);text(s.detail)
  if s.toast~='' and r.time_precise()<s.toast_until then I.TextColored(ctx,green,s.toast) end
  I.Spacing(ctx)
  button(s.details and 'Hide file results' or 'Show file results',function()s.details=not s.details end,#s.results==0)
  I.SameLine(ctx)
  button('Show in Wwise',function()
    local c=s.containers[s.selected_container];assert(c,'No successfully updated container in this batch')
    if not w:show(c.id,profile) then toast('Container selected. Switch to Wwise to view it.') end
  end,s.busy or #s.containers==0 or not w.connected)
  if #s.containers>1 then
    if I.BeginCombo(ctx,'Container',C.basename(s.containers[s.selected_container].path)) then
      for i,c in ipairs(s.containers) do if I.Selectable(ctx,c.path,i==s.selected_container) then s.selected_container=i end end
      I.EndCombo(ctx)
    end
  end
  if s.details then
    I.Separator(ctx)
    for i,v in ipairs(s.results) do
      I.PushID(ctx,i);I.TextColored(ctx,v.state=='Converted' and green or amber,C.basename(v.path)..' — '..v.state)
      if v.link then text('Matched: '..(v.link.sound_path or v.link.source_path or '')) end
      text(v.message);I.PopID(ctx)
    end
    button('Retry skipped / failed files',retry_failed,s.busy or not w.connected)
  end
  if s.error then
    I.Separator(ctx);I.TextColored(ctx,amber,'Attention');text(s.error)
    button('Dismiss message',function()s.error=nil end)
  end
end
local function setup_tab()
  I.BeginDisabled(ctx,s.busy or s.enabled)
  local changed,port=I.InputInt(ctx,'WAAPI port',profile.port)
  if changed then profile.port=math.max(1,math.min(65535,port));save() end
  button('Connect to Wwise',connect)
  if s.connected_project then
    text(s.connected_project.file)
    button('Use this project',pin)
  end
  if profile.project_path then I.Separator(ctx);text('Pinned: '..profile.project_path) end
  if w.platforms and I.BeginCombo(ctx,'Platform',platform_name()) then
    for _,p in ipairs(w.platforms) do if I.Selectable(ctx,p.name,p.id==profile.platform) then profile.platform=p.id;profile.platform_name=p.name;save() end end
    I.EndCombo(ctx)
  end
  local ch,val=I.Checkbox(ctx,'Show success confirmation',profile.notify)
  if ch then profile.notify=val;save() end
  text('Automatic matching: WAV filename (without .wav) = existing Wwise Sound name. Duplicate or missing matches are skipped.')
  text('Conversion uses existing Wwise settings. No object creation, imports, SoundBanks, or WAV backups.')
  I.EndDisabled(ctx)
  if s.enabled then text('Pause updates to change setup.') end
  if s.error then I.Separator(ctx);text(s.error) end
end
local function ui()
  I.SetNextWindowSize(ctx,440,300,I.Cond_FirstUseEver)
  local visible,open=I.Begin(ctx,'Wwise Relay',true)
  if visible then
    I.Text(ctx,profile.project_name or 'No Wwise project linked')
    I.BeginDisabled(ctx,s.busy or not win)
    local changed,enabled=I.Checkbox(ctx,'Update after render',s.enabled)
    if changed then
      if enabled then guard(enable) else fs:close_monitor();s.enabled=false;s.detector:cancel();s.pending={};s.status='Updates paused';s.detail='Enable to follow future renders.' end
    end
    I.EndDisabled(ctx)
    I.TextColored(ctx,muted,(w.connected and ('Connected · '..platform_name()) or 'Not connected')..'  |  v'..C.VERSION)
    if not win then I.TextColored(ctx,amber,'UI preview — live updates require Windows') end
    if I.BeginTabBar(ctx,'views') then
      for _,t in ipairs({'Latest render','Setup'}) do
        local flags=s.tab==t and I.TabItemFlags_SetSelected or 0
        if I.BeginTabItem(ctx,t,nil,flags) then
          if s.tab==t then s.tab=nil end
          if t=='Latest render' then render_tab() else setup_tab() end
          I.EndTabItem(ctx)
        end
      end
      I.EndTabBar(ctx)
    end
    I.Separator(ctx);I.TextColored(ctx,muted,(s.busy and 'Processing render' or s.enabled and 'Enabled · waiting for render' or 'Paused')..'   |   Existing audio only')
    I.End(ctx)
  end
  return open
end
local _,_,section,command=r.get_action_context()
r.SetToggleCommandState(section,command,1);r.RefreshToolbar2(section,command)
r.atexit(function()
  fs:close_monitor()
  r.DeleteExtState(C.SECTION,heartbeat_key,false)
  r.SetToggleCommandState(section,command,0);r.RefreshToolbar2(section,command)
  -- Do not disconnect ReaWwise's shared connection or clear other scripts' JSON.
end)
local function loop()
  guard(tick)
  local ok,open=pcall(ui)
  if not ok then r.MB(tostring(open),'Wwise Relay — UI error',0);return end
  if open then r.defer(loop) end
end
loop()
