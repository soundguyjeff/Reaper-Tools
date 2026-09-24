-- Exercise the full panel loop with simulated REAPER/Wwise/file adapters.
local C=require('relay.core')
local total=0
local function scenario(mode)
  local now,click,toggle,report=0,nil,false,'FILE:C:\\render.wav;'
  local replaced,converted,shown=0,0,0
  local next_frame,exit_cb
  local ui_frames,closed=0,0
  local attempts,attempt_times=0,{}
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
  function w:project()
    if mode=='disconnect' and now>=5 and now<20 then error('Wwise closed') end
    local wrong=mode=='wrong_project' or (mode=='wrong_then_right' and now<10)
    return {id=id,file=wrong and 'C:\\other.wproj' or 'C:\\game.wproj'}
  end
  function w:connect()
    attempts=attempts+1;attempt_times[#attempt_times+1]=now
    if mode=='never_available' or (mode=='late_start' and now<10) then error('Wwise unavailable') end
    if mode=='connect_stall' then for _=1,1000 do coroutine.yield() end end
    self.connected=true;return self:project(),{}
  end
  function w:catalog(p) assert(self:project().file==p.project_path,'Wrong project');return {} end
  function w:match(path)
    if mode=='unknown' or (mode=='mixed' and path:find('unknown',1,true)) then return nil,'No existing Wwise Sound named unlinked.' end
    if mode=='ambiguous' then return nil,'More than one Wwise Sound is named render.' end
    local result={};for k,v in pairs(link) do result[k]=v end;result.render=path;return result
  end
  function w:verify() assert(mode~='identity_changed','Identity changed') end
  local checkout_done=false
  function w:checkout() assert(mode~='checkout_failure','Checkout failed');checkout_done=true end
  function w:content_hash() return id end
  function w:refresh() assert(mode~='refresh_failure','Source refresh failed');return id end
  function w:convert() converted=converted+1;if mode=='convert_stall' then for _=1,1000 do coroutine.yield() end end;assert(mode~='conversion_failure','Conversion failed');return 'C:\\cache.wem' end
  function w:show() shown=shown+1;return true end
  local fs={probes=0}
  function fs:close_monitor()closed=closed+1 end
  function fs:inspect(paths) if mode=='file_stall' and paths[1]=='C:\\original.wav' then for _=1,1000 do coroutine.yield() end end;local out={};for _,p in ipairs(paths) do out[#out+1]={readOnly=(p=='C:\\original.wav' and (mode=='checkout_success' or mode=='checkout_failure' or mode=='checkout_still_readonly') and (not checkout_done or mode=='checkout_still_readonly')),ok=true,path=p,stamp='1:44',sha=replaced>0 and 'new' or 'old'} end;return out end
  function fs:begin_inspect(paths) return {paths=paths} end
  function fs:poll(job)
    self.probes=self.probes+1
    local out=self:inspect(job.paths)
    for _,v in ipairs(out) do
      v.stamp=(mode=='disconnect' or mode=='late_start' or mode=='wrong_then_right') and '1:44' or '2:44'
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
  I.Begin=function()ui_frames=ui_frames+1;return true,true end
  I.BeginTabBar=function()return true end
  I.BeginTabItem=function()return true end
  I.Button=function(_,name) if name==click then click=nil;return true end;return false end
  I.Checkbox=function(_,name,v)if name=='Update after render' and toggle then toggle=false;return true,true end;return false,v end
  I.InputInt=function(_,_,v)return false,v end
  I.TextColored=function(_,_,v)messages[#messages+1]=v end
  I.TextWrapped=function(_,v)messages[#messages+1]=v end
  package.loaded.imgui=nil;package.preload.imgui=function()return function()return I end end
  reaper={ImGui_GetBuiltinPath=function()return '.'end,GetOS=function()return mode=='mac_preview' and 'OSX64' or 'Win64'end,
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
  local function frames(n) for _=1,n do next_frame() end end
  frames(5) -- Startup connects without clicking any button.
  if mode=='mac_preview' then
    now=100;frames(10);assert(attempts==0 and replaced==0);exit_cb();total=total+1;return
  end
  if mode=='never_available' or mode=='late_start' or mode=='wrong_then_right' then
    assert(attempts==1 and not w.connected)
    now=1;frames(20);assert(attempts==1,'Retry ran before its delay')
    for _,t in ipairs({2,6,14,30,60}) do now=t;frames(10) end
    assert(replaced==0 and converted==0,'Auto-connect performed an audio update')
    if mode=='never_available' then
      assert(attempts==6 and not w.connected)
      for i,t in ipairs({0,2,6,14,30,60}) do assert(attempt_times[i]==t,'Retry backoff changed') end
    else assert(w.connected and attempts==4,'Did not recover when the saved project became available') end
    exit_cb();total=total+1;return
  end
  if mode=='disconnect' then
    assert(w.connected and attempts==1)
    frames(4)
    for _,t in ipairs({2,3,5,7,11,19,35,40}) do now=t;frames(10) end
    assert(w.connected and attempts>1,'Did not reconnect after Wwise restarted')
    assert(replaced==0 and converted==0,'Reconnection replayed audio')
    assert(table.concat(messages,'\n'):find('Audio updates are paused',1,true))
    exit_cb();total=total+1;return
  end
  if mode=='connect_stall' then
    local before=ui_frames;frames(100);assert(ui_frames==before+100 and replaced==0)
    click='Stop waiting';frames(2);assert(closed>0 and table.concat(messages,'\n'):find('Stopped waiting',1,true))
    now=100;frames(30);assert(attempts==1,'Stop waiting must suppress automatic retries')
    click='Resume auto-connect';frames(5);assert(attempts==2,'Resume did not restart the connection')
    exit_cb();total=total+1;return
  end
  if mode=='fresh_setup' then click='Use this project';frames(3) end
  frames(3) -- Existing pinned projects arm automatically, without a checkbox click.
  if mode=='unknown' then report='FILE:C:\\unlinked.wav;' end
  if mode=='competing_outputs' then report='FILE:C:\\one\\render.wav;FILE:C:\\two\\render.wav;' end
  if mode=='new_filename' then report='FILE:C:\\new.wav;' end
  if mode=='mixed' then report='FILE:C:\\render.wav;FILE:C:\\unknown.wav;' end
  for _,t in ipairs({2,2.1,3.6,3.7,4.2,4.3,4.4,6,8,10,12,14}) do now=t;frames(10) end
  local text=table.concat(messages,'\n')
  if mode=='convert_stall' or mode=='file_stall' then
    local before=ui_frames;frames(100);assert(ui_frames==before+100)
    assert(not text:find('Wwise audio updated',1,true))
    assert(replaced==(mode=='convert_stall' and 1 or 0))
    click='Stop waiting';frames(2);assert(closed>0)
    local count=replaced;frames(50);assert(replaced==count,'Stopped task resumed a replacement')
    exit_cb();total=total+1;return
  end
  if mode=='checkout_success' or mode=='success' or mode=='legacy_profile' or mode=='new_filename' or mode=='fresh_setup' or mode=='temporary_lock' then
    assert(replaced==1 and converted==1 and text:find('Wwise audio updated',1,true))
    click='Show in Wwise';frames(3);assert(shown==1,'Show must target successful container')
  elseif mode=='inspection_failure' then
    assert(replaced==0 and converted==0 and text:find('WAV is locked or unreadable',1,true) and text:find('Updates paused',1,true))
  elseif mode=='mixed' then
    assert(replaced==1 and converted==1 and text:find('1 skipped',1,true) and not text:find('Wwise audio updated',1,true))
  elseif mode=='refresh_failure' then
    assert(replaced==1 and converted==0 and not text:find('Wwise audio updated',1,true))
  elseif mode=='conversion_failure' or mode=='stale_artifact' then
    assert(replaced==1 and converted==1 and not text:find('Wwise audio updated',1,true))
    assert(text:find('updates paused',1,true),'Failed conversion must pause')
  else assert(replaced==0 and converted==0,'Rejected case wrote audio: '..mode) end
  if mode=='legacy_profile' then assert(saved_profile.version==2 and saved_profile.links==nil,'Old manual links must not be reused') end
  assert(not text:find('Save approved link',1,true))
  exit_cb();total=total+1
end
for _,mode in ipairs({'checkout_success','checkout_failure','checkout_still_readonly','never_available','late_start','wrong_then_right','disconnect','mac_preview','connect_stall','convert_stall','file_stall','success','wrong_project','identity_changed','conversion_failure','refresh_failure','stale_artifact','unknown','project_switched','identity_reused','missing_master','invalid_identity','legacy_profile','new_filename','ambiguous','competing_outputs','mixed','fresh_setup','inspection_failure','temporary_lock'}) do scenario(mode) end
return total
