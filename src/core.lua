local M = { VERSION = '0.3.3', SECTION = 'WwiseRelay' }

-- Optional frame budget installed by the panel; tests and non-UI use need no hook.
function M.checkpoint() if M.yield_hook then M.yield_hook() end end

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
      if i%2048==0 then M.checkpoint() end
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
    M.checkpoint()
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
    M.checkpoint()
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
  for _,s in ipairs(all_sources) do M.checkpoint(); if M.key(s.original)==M.key(link.original) then count=count+1;assert(s.id==link.source_id,'Original WAV is shared by another Wwise source') end end
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
