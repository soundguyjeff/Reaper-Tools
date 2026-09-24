local C=require('relay.core')
local M={};M.__index=M
local allow={
 ['ak.wwise.core.object.get']=true,['ak.wwise.core.getInfo']=true,
 ['ak.wwise.core.getProjectInfo']=true,
 ['ak.wwise.core.audio.convert']=true,['ak.wwise.ui.commands.execute']=true,
 ['ak.wwise.ui.bringToForeground']=true,
}
function M.new(r,port,backend) return setmetatable({r=r,port=port or 8080,backend=backend,connected=false},M) end
local function operation_name(uri,args)
  if uri=='ak.wwise.core.object.get' then
    local from=(args or {}).from or {}
    if from.ofType then return 'Read Wwise '..table.concat(from.ofType,', ')..' objects' end
    if from.id then return 'Read Wwise object '..tostring(from.id[1]) end
    return 'Find Wwise objects'
  end
  return ({['ak.wwise.core.getInfo']='Read Wwise version',
    ['ak.wwise.core.getProjectInfo']='Read Wwise project settings',
    ['ak.wwise.core.audio.convert']='Convert matched Wwise audio',
    ['ak.wwise.ui.commands.execute']='Show container in Wwise',
    ['ak.wwise.ui.bringToForeground']='Bring Wwise forward'})[uri] or uri
end
function M:call(uri,args,options,read,operation)
  assert(allow[uri],'Wwise operation is not permitted')
  if uri=='ak.wwise.ui.commands.execute' then assert(args.command=='FindInProjectExplorerSyncGroup1','Only navigation is permitted') end
  if uri=='ak.wwise.core.audio.convert' then
    assert(#args.objects==1 and C.guid(args.objects[1]),'Conversion must target one matched audio source')
    assert(#args.platforms==1 and #args.languages==1 and args.languages[1]=='SFX','Conversion scope is invalid')
  end
  local data=self.backend:run({action='waapi',port=self.port,uri=uri,args=args or {},options=options or {},operation=operation or operation_name(uri,args)}).data
  assert(type(data)=='table','Wwise returned no result object')
  local Q={}
  function Q.get(p,k) return p and p[k] end
  function Q.text(p,k) local v=k and Q.get(p,k) or p;return type(v)=='string' and v or '' end
  function Q.list(p,k,reader)
    local a=k and Q.get(p,k) or p;local out={}
    for _,v in ipairs(a or {}) do C.checkpoint();out[#out+1]=reader(v) end
    return out
  end
  return read and read(Q,data) or true
end
local function read_object(Q,p)
  local par=Q.get(p,'parent')
  return {id=Q.text(p,'id'),name=Q.text(p,'name'),type=Q.text(p,'type'),path=Q.text(p,'path'),
    original=Q.text(p,'originalWavFilePath'),file=Q.text(p,'filePath'),
    content_hash=Q.text(p,'contentHash'),converted=Q.text(p,'convertedWemFilePath'),parent_id=par and Q.text(par,'id') or ''}
end
local fields={'id','name','type','path','parent','filePath','originalWavFilePath'}
function M:objects(from,extra)
  local opt={['return']=fields};if extra then opt=extra end
  return self:call('ak.wwise.core.object.get',{from=from},opt,function(Q,p)return Q.list(p,'return',function(x)return read_object(Q,x)end)end)
end
-- WAQL string literals use literal backslashes, unlike JSON strings. Reject
-- quotes/control characters (illegal in Windows WAV paths) before constructing
-- a query, then JSON-encode the complete request normally in the file backend.
local function waql_string(value)
  assert(type(value)=='string' and not value:find('[%z\1-\31"]'),'Unsupported character in Wwise lookup')
  return '"'..value..'"'
end
function M:query(waql,extra,operation)
  return self:call('ak.wwise.core.object.get',{waql=waql},extra or {['return']=fields},
    function(Q,p)return Q.list(p,'return',function(x)return read_object(Q,x)end)end,operation)
end
function M:matching_sounds(path)
  local name=C.sound_name(path);assert(name,'Expected a local rendered WAV filename')
  return self:query('from type Sound where name = '..waql_string(name),
    {['return']={'id','name','type','path','parent'}},'Find Sound named "'..name..'"')
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
  self.connected=false
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
function M:sources(original)
  local a=self:query('from type AudioFileSource where originalWavFilePath = '..waql_string(original),
    {['return']={'id','type','parent','originalWavFilePath'}},'Check original WAV ownership')
  local prefix=C.key(self.originals)..'\\sfx\\'
  for _,s in ipairs(a) do C.checkpoint(); s.language=C.key(s.original):sub(1,#prefix)==prefix and 'SFX' or 'Other' end
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
  -- A validated batch context, never a copy of the entire Wwise project.
  return {}
end
function M:active_source(sound_id,platform)
  return self:call('ak.wwise.core.object.get',{from={id={sound_id}}},{['return']={'activeSource'},platform=platform},function(Q,p)
    return Q.list(p,'return',function(x)return Q.text(Q.get(x,'activeSource'),'id')end)[1]
  end)
end
function M:match(path,profile,catalog)
  local sound,reason=C.match_sound(path,self:matching_sounds(path))
  if not sound then return nil,reason end
  local active=self:active_source(sound.id,profile.platform)
  local source=C.guid(active) and self:objects({id={active}})[1]
  if not source or source.type~='AudioFileSource' then return nil,'The matched sound has no active file-based audio source on the selected platform.' end
  if not C.absolute(source.original) then return nil,'The active source has no local original WAV path.' end
  local prefix=C.key(self.originals)..'\\sfx\\'
  source.language=C.key(source.original):sub(1,#prefix)==prefix and 'SFX' or 'Other'
  if source.language~='SFX' then return nil,'Only SFX sources are supported in this release' end
  local owners=self:sources(source.original)
  local link={render=path,source_id=source.id,sound_id=sound.id,container_id=sound.parent_id,
    sound_name=sound.name,sound_path=sound.path,source_path=source.path,original=source.original,
    project_id=profile.project_id,project_path=profile.project_path}
  local ok,err=pcall(C.validate_link,link,source,owners,profile.project_id,profile.project_path)
  if not ok then return nil,tostring(err) end
  local container=self:object(sound.parent_id)
  link.container_path=container.path
  return link
end
function M:verify(link,profile)
  self:check_project(profile)
  local sound,reason=C.match_sound(link.render,self:matching_sounds(link.render))
  assert(sound,reason)
  assert(sound.id==link.sound_id,'The matching Wwise sound changed during the update')
  assert(sound.parent_id==link.container_id,'Sound moved to another container during the update; render again')
  local live=self:object(link.source_id)
  local prefix=C.key(self.originals)..'\\sfx\\'
  live.language=C.key(live.original):sub(1,#prefix)==prefix and 'SFX' or 'Other'
  C.validate_link(link,live,self:sources(live.original),profile.project_id,profile.project_path)
  assert(self:active_source(sound.id,profile.platform)==link.source_id,'Active Wwise source changed; update skipped')
  return true
end
function M:content_hash(link,platform)
  local source=self:object(link.source_id,{['return']={'id','contentHash'},platform=platform})
  assert(C.guid(source.content_hash),'Wwise returned no source content identity')
  return source.content_hash
end
function M:refresh(link,profile,previous_hash,audio_changed)
  self:verify(link,profile)
  self.backend:run({action='refresh',port=self.port,projectId=profile.project_id,projectPath=profile.project_path,
    sourceId=link.source_id,soundId=link.sound_id,original=link.original,platform=profile.platform,
    operation='Refresh existing Wwise audio'})
  local deadline=self.r.time_precise()+10
  repeat
    local hash=self:content_hash(link,profile.platform)
    if not audio_changed or hash~=previous_hash then return hash end
    local next_poll=self.r.time_precise()+0.25
    repeat coroutine.yield() until self.r.time_precise()>=next_poll
  until self.r.time_precise()>=deadline
  error('Wwise still reports the previous audio after refreshing. Updates paused; no success was reported.',0)
end
function M:convert(link,platform,expected_hash)
  assert(C.guid(expected_hash),'Refreshed source identity is required before conversion')
  local errors=self:call('ak.wwise.core.audio.convert',{objects={link.source_id},platforms={platform},languages={'SFX'}},{},function(Q,p)
    local a=Q.get(p,'errors');assert(a,'Wwise returned no conversion report')
    return Q.list(a,nil,function(x)return {severity=Q.text(x,'severity'),message=Q.text(x,'message')}end)
  end)
  local ok,message=C.conversion_status(errors);assert(ok,message)
  local source=self:object(link.source_id,{['return']={'id','convertedWemFilePath','contentHash'},platform=platform})
  assert(source.content_hash==expected_hash,'Source content changed during conversion; updates paused')
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
