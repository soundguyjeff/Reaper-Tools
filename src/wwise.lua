local C=require('relay.core')
local M={};M.__index=M
local allow={
 ['ak.wwise.core.object.get']=true,['ak.wwise.core.getInfo']=true,
 ['ak.wwise.core.getProjectInfo']=true,
 ['ak.wwise.core.audio.convert']=true,['ak.wwise.ui.commands.execute']=true,
 ['ak.wwise.ui.bringToForeground']=true,
}
function M.new(r,port,backend) return setmetatable({r=r,port=port or 8080,backend=backend,connected=false},M) end
function M:call(uri,args,options,read)
  assert(allow[uri],'Wwise operation is not permitted')
  if uri=='ak.wwise.ui.commands.execute' then assert(args.command=='FindInProjectExplorerSyncGroup1','Only navigation is permitted') end
  if uri=='ak.wwise.core.audio.convert' then
    assert(#args.objects==1 and C.guid(args.objects[1]),'Conversion must target one matched audio source')
    assert(#args.platforms==1 and #args.languages==1 and args.languages[1]=='SFX','Conversion scope is invalid')
  end
  local data=self.backend:run({action='waapi',port=self.port,uri=uri,args=args or {},options=options or {}}).data
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
function M:sources()
  local a=self:objects({ofType={'AudioFileSource'}})
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
  for _,candidate in ipairs(catalog.sources) do C.checkpoint(); if candidate.id==active then source=candidate end end
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
  for _,s in ipairs(catalog.sources) do C.checkpoint(); if s.id==link.source_id then live=s end end
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
