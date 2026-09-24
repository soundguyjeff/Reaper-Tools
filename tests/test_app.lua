-- Exercise the full panel loop with simulated REAPER/Wwise/file adapters.
local C=require('relay.core')
local total=0
local function scenario(mode)
  local now,click,toggle,report=0,nil,false,'FILE:C:\\render.wav;'
  local replaced,converted,shown=0,0,0
  local next_frame,exit_cb
  local messages={}
  local master={}
  local startup_message
  local id='{11111111-1111-1111-1111-111111111111}'
  local link={render='C:\\render.wav',original='C:\\original.wav',source_id=id,sound_id=id,container_id=id,
    project_id=id,project_path='C:\\game.wproj',destination_sha='old',sound_path='\\Actor-Mixer Hierarchy\\Container\\render',container_path='\\Actor-Mixer Hierarchy\\Container'}
  local profile={version=2,port=8080,platform=id,project_id=id,project_path='C:\\game.wproj',notify=true}
  if mode=='legacy_profile' then profile.version=1;profile.links=C.array({{render='C:\\wrong.wav',source_id='obsolete'}}) end
  local saved_profile
  local w={connected=false,platforms={{id=id,name='Windows'}}}
  function w:project() return {id=id,file=mode=='wrong_project' and 'C:\\other.wproj' or 'C:\\game.wproj'} end
  function w:connect() self.connected=true;return self:project(),{} end
  function w:catalog(p) assert(self:project().file==p.project_path,'Wrong project');return {} end
  function w:match(path)
    if mode=='unknown' or (mode=='mixed' and path:find('unknown',1,true)) then return nil,'No existing Wwise Sound named unlinked.' end
    if mode=='ambiguous' then return nil,'More than one Wwise Sound is named render.' end
    local result={};for k,v in pairs(link) do result[k]=v end;result.render=path;return result
  end
  function w:verify() assert(mode~='identity_changed','Identity changed') end
  function w:convert() converted=converted+1;assert(mode~='conversion_failure','Conversion failed');return 'C:\\cache.wem' end
  function w:show() shown=shown+1;return true end
  local fs={probes=0}
  function fs:close_monitor()end
  function fs:inspect(paths) local out={};for _,p in ipairs(paths) do out[#out+1]={ok=true,path=p,stamp='1:44',sha='old'} end;return out end
  function fs:begin_inspect(paths) return {paths=paths} end
  function fs:poll(job)
    self.probes=self.probes+1
    local out=self:inspect(job.paths)
    for _,v in ipairs(out) do
      v.stamp='2:44'
      if mode=='inspection_failure' or (mode=='temporary_lock' and self.probes==1) then v.ok=false;v.error='WAV is locked or unreadable' end
    end
    return out
  end
  function fs:replace() replaced=replaced+1;return {sha='new',stamp='2:44'} end
  function fs:artifact() assert(mode~='stale_artifact','Stale converted media');return true end
  package.loaded['relay.wwise']=nil;package.preload['relay.wwise']=function()return {new=function()return w end}end
  package.loaded['relay.files']=nil;package.preload['relay.files']=function()return {new=function()return fs end}end
  package.loaded['relay.worker']=nil;package.preload['relay.worker']=function()return ''end
  local I=setmetatable({Cond_FirstUseEver=1,TabItemFlags_SetSelected=1},{__index=function()return function()end end})
  I.CreateContext=function()return {}end
  I.Begin=function()return true,true end
  I.BeginTabBar=function()return true end
  I.BeginTabItem=function()return true end
  I.Button=function(_,name) if name==click then click=nil;return true end;return false end
  I.Checkbox=function(_,name,v)if name=='Update after render' and toggle then toggle=false;return true,true end;return false,v end
  I.InputInt=function(_,_,v)return false,v end
  I.TextColored=function(_,_,v)messages[#messages+1]=v end
  I.TextWrapped=function(_,v)messages[#messages+1]=v end
  package.loaded.imgui=nil;package.preload.imgui=function()return function()return I end end
  reaper={ImGui_GetBuiltinPath=function()return '.'end,GetOS=function()return 'Win64'end,
    EnumProjects=function()return mode=='project_switched' and now>2 and 2 or 1 end,
    -- Deliberately no GetProjectGUID: it does not exist in native REAPER.
    GetMasterTrack=function(project) assert(project==1);if mode~='missing_master' then return master end end,
    GetTrackGUID=function(track)
      assert(track==master,'Identity must come from the master track')
      if mode=='invalid_identity' then return '' end
      if mode=='identity_reused' and now>2 then return '{22222222-2222-2222-2222-222222222222}' end
      return id
    end,
    GetExtState=function(_,key)return mode~='fresh_setup' and key:match('^profile:') and C.json(profile) or ''end,
    SetExtState=function(_,key,value)if key:match('^profile:') then saved_profile=C.decode(value) end end,DeleteExtState=function()end,time_precise=function()return now end,
    GetSetProjectInfo_String=function()return true,report end,get_action_context=function()return 0,0,0,1 end,
    SetToggleCommandState=function()end,RefreshToolbar2=function()end,atexit=function(f)exit_cb=f end,
    defer=function(f)next_frame=f end,MB=function(message)startup_message=message end}
  assert(loadfile(ROOT..'/src/app.lua'))()
  assert(replaced==0 and converted==0,'Startup must never write audio')
  if mode=='missing_master' or mode=='invalid_identity' then
    assert(startup_message and startup_message:find('Could not identify',1,true))
    assert(not next_frame,'Invalid identity must stop before the update loop')
    total=total+1;return
  end
  assert(not startup_message,'Unexpected startup error: '..tostring(startup_message))
  assert(next_frame,'Startup must reach the panel with native APIs only')
  click='Connect to Wwise';next_frame()
  if mode=='fresh_setup' then click='Use this project';next_frame() end
  toggle=true;next_frame()
  if mode=='unknown' then report='FILE:C:\\unlinked.wav;' end
  if mode=='competing_outputs' then report='FILE:C:\\one\\render.wav;FILE:C:\\two\\render.wav;' end
  if mode=='new_filename' then report='FILE:C:\\new.wav;' end
  if mode=='mixed' then report='FILE:C:\\render.wav;FILE:C:\\unknown.wav;' end
  for _,t in ipairs({2,2.1,3.6,3.7,4.2,4.3,4.4,6,8,10,12,14}) do now=t;next_frame() end
  local text=table.concat(messages,'\n')
  if mode=='success' or mode=='legacy_profile' or mode=='new_filename' or mode=='fresh_setup' or mode=='temporary_lock' then
    assert(replaced==1 and converted==1 and text:find('Wwise audio updated',1,true))
    click='Show in Wwise';next_frame();assert(shown==1,'Show must target successful container')
  elseif mode=='inspection_failure' then
    assert(replaced==0 and converted==0 and text:find('WAV is locked or unreadable',1,true) and text:find('Updates paused',1,true))
  elseif mode=='mixed' then
    assert(replaced==1 and converted==1 and text:find('1 skipped',1,true) and not text:find('Wwise audio updated',1,true))
  elseif mode=='conversion_failure' or mode=='stale_artifact' then
    assert(replaced==1 and converted==1 and not text:find('Wwise audio updated',1,true))
    assert(text:find('updates paused',1,true),'Failed conversion must pause')
  else assert(replaced==0 and converted==0,'Rejected case wrote audio: '..mode) end
  if mode=='legacy_profile' then assert(saved_profile.version==2 and saved_profile.links==nil,'Old manual links must not be reused') end
  assert(not text:find('Save approved link',1,true))
  exit_cb();total=total+1
end
for _,mode in ipairs({'success','wrong_project','identity_changed','conversion_failure','stale_artifact','unknown','project_switched','identity_reused','missing_master','invalid_identity','legacy_profile','new_filename','ambiguous','competing_outputs','mixed','fresh_setup','inspection_failure','temporary_lock'}) do scenario(mode) end
return total
