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
local fs=F.new(r,worker)
local w=W.new(r,profile.port,fs)
local s={startup_arm=true,enabled=false,status='Waiting for Wwise',detail='Relay connects automatically. Open Wwise with WAAPI enabled.',error=startup_error,
  results={},containers={},details=false,detector=C.detector(),job=nil,next_probe=0,last_stats='',pending={},busy=false,
  tab='Setup',toast='',toast_until=0,selected_container=1,last_files={},
  auto_connect=true,next_connection=0,retry_delay=2,connection_status='Waiting for Wwise',connection_detail=''}
local heartbeat_key='instance:'..project_guid
local now=r.time_precise()
local prior=tonumber(r.GetExtState(C.SECTION,heartbeat_key)) or 0
if prior>0 and math.abs(now-prior)<4 then r.MB('Wwise Relay is already running for this REAPER project.','Wwise Relay',0);return end
r.SetExtState(C.SECTION,heartbeat_key,tostring(now),false)
local function save() r.SetExtState(C.SECTION,key,C.json(profile),true) end
local function toast(text) s.toast=text;s.toast_until=r.time_precise()+6 end
local function pause(message)
  fs:close_monitor()
  s.startup_arm=false;s.enabled=false;s.detector:cancel();s.pending={};s.job=nil;s.busy=false;s.error=tostring(message);s.toast='';s.status='Updates paused';s.detail='Resolve the issue, then enable updates again.'
end
local function schedule(fn)
  if s.task then return end
  s.task=coroutine.create(fn);s.working=true
end
local frame_deadline=0
C.yield_hook=function()
  if coroutine.isyieldable() and r.time_precise()>=frame_deadline then coroutine.yield() end
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
  w.port=profile.port;s.connection_status='Connecting to Wwise';s.connection_detail=''
  if not s.error and #s.results==0 and not s.enabled then s.status='Connecting to Wwise';s.detail='REAPER remains available while connecting.' end
  coroutine.yield()
  local p,info=w:connect()
  if profile.project_id then assert(matched_project(p),'Open the pinned project in Wwise: '..profile.project_path) end
  s.connected_project=p;s.info=info
  s.connection_status='Connected';s.connection_detail=''
  if not s.error and #s.results==0 and not s.enabled then
    s.status='Connected';s.detail=profile.project_id and 'Enable Update after render when you are ready.' or 'Choose Use this project and your platform in Setup.'
  end
end
-- Connection attempts are read-only and use the same yielding background path
-- as transfers. A reconnect never enables updates or retries an uncertain write.
local function connection_tick(time)
  if not win or not s.auto_connect or s.job or s.busy or time<s.next_connection then return end
  if w.connected then
    local ok,p=pcall(function()
      local live=w:project()
      if profile.project_id then assert(matched_project(live),'Open the pinned project in Wwise: '..profile.project_path)
      elseif s.connected_project then assert(live.id==s.connected_project.id and C.key(live.file)==C.key(s.connected_project.file),'Wwise project changed') end
      return live
    end)
    if ok then s.next_connection=r.time_precise()+5;return end
    w.connected=false;s.connected_project=nil
    fs:close_monitor()
    if s.enabled then pause('Wwise connection changed or became unavailable. Audio updates are paused; re-enable them after reconnection.') end
    s.connection_status='Waiting for Wwise';s.connection_detail=tostring(p)
    s.next_connection=r.time_precise()+2;s.retry_delay=2
    return
  end
  local ok,err=pcall(connect)
  if ok then
    s.retry_delay=2;s.next_connection=r.time_precise()+5
  else
    w.connected=false;s.connected_project=nil;fs:close_monitor()
    s.connection_status='Waiting for Wwise';s.connection_detail=tostring(err)
    s.next_connection=r.time_precise()+s.retry_delay;s.retry_delay=math.min(s.retry_delay*2,30)
    if not s.error and #s.results==0 then
      s.status='Waiting for Wwise';s.detail=profile.project_id and 'Reconnecting automatically. Open the saved Wwise project with WAAPI enabled.' or 'Reconnecting automatically. Open Wwise with WAAPI enabled.'
    end
  end
end
local function retry_connection()
  s.auto_connect=true;s.next_connection=0;s.retry_delay=2
  s.connection_status='Waiting for Wwise';s.connection_detail=''
end
local function pin()
  assert(w.connected and s.connected_project,'Waiting for a Wwise connection')
  current_project()
  assert(not profile.project_id or matched_project(s.connected_project),'The pinned Wwise project must remain open')
  profile.project_id=s.connected_project.id;profile.project_path=s.connected_project.file;profile.project_name=s.connected_project.name
  if profile.platform=='' then
    for _,p in ipairs(w.platforms) do if p.name=='Windows' then profile.platform=p.id end end
    if profile.platform=='' then profile.platform=w.platforms[1].id end
  end
  save();toast('Project pinned. Relay is ready to follow renders.')
end
local function platform_name()
  for _,p in ipairs(w.platforms or {}) do if p.id==profile.platform then return p.name end end
  return profile.platform_name or 'Choose platform'
end
local function enable()
  fs:close_monitor();s.inspect_failure=nil
  current_project();assert(win,'Live updates require Windows');assert(w.connected,'Waiting for Wwise to connect automatically')
  assert(profile.project_id,'Choose Use this project in Setup first')
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
  s.status='Finding matching Wwise sounds';s.detail='Reading the pinned project in the background.'
  coroutine.yield()
  s.tab='Latest render';s.results={};s.containers={};s.selected_container=1;s.error=nil;s.toast=''
  s.busy=true;s.status='Refreshing rendered WAV batch';s.detail='Matching, native refresh and conversion run as one batch.'
  local result=w:batch(items,profile)
  s.results=result.items or {}
  for _,row in ipairs(s.results) do
    if row.state=='Converted' and row.link then
      local have=false;for _,v in ipairs(s.containers) do if v.id==row.link.container_id then have=true end end
      if not have then s.containers[#s.containers+1]={id=row.link.container_id,path=row.link.container_path} end
    elseif row.state=='Failed' then s.error=row.message end
  end
  s.pending={};s.busy=false
  summary()
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
  if s.busy then return end
  connection_tick(time)
  if s.startup_arm and w.connected and profile.project_id then
    s.startup_arm=false;enable()
  end
  if not s.enabled or not w.connected then return end
  current_project()
  local report=stats()
  if report=='' then
    if s.job then fs:close_monitor() end
    s.detector:cancel();s.last_stats='';s.last_files={};s.job=nil;s.inspect_failure=nil;return
  end
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
  -- Finish the outstanding inspection before submitting any Wwise/file operation.
  if not s.job and not s.inspect_failure then
    local ready=s.detector:take(time)
    if ready then begin_batch(ready);return end
  end
  if not s.job and time>=s.next_probe then
    s.job=fs:begin_inspect(files);s.job.report=report;s.next_probe=time+1.5;s.last_stats=report;s.last_files=files
  end
end

local green,amber,red,muted=0x95D5AEFF,0xEDC28AFF,0xEBA0A0FF,0xB0B5BEFF
local function text(s) I.TextWrapped(ctx,tostring(s or '')) end
local function button(label,fn,disabled)
  I.BeginDisabled(ctx,disabled or s.working or false)
  if I.Button(ctx,label) then schedule(fn) end
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
  I.BeginDisabled(ctx,s.busy or s.enabled or s.working)
  local changed,port=I.InputInt(ctx,'WAAPI port',profile.port)
  if changed then
    profile.port=math.max(1,math.min(65535,port));save()
    w.connected=false;s.connected_project=nil;fs:close_monitor();retry_connection()
  end
  if not w.connected then button(s.auto_connect and 'Retry now' or 'Resume auto-connect',retry_connection) end
  if w.connected and s.connected_project then
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
  text('Conversion uses existing Wwise settings. Existing sources only. No new audio, SoundBanks, or WAV backups.')
  I.EndDisabled(ctx)
  if s.enabled then text('Pause updates to change setup.') end
  if s.connection_detail~='' then text(s.connection_detail) end
  if s.error then I.Separator(ctx);text(s.error) end
end
local function ui()
  I.SetNextWindowSize(ctx,440,300,I.Cond_FirstUseEver)
  local visible,open=I.Begin(ctx,'Wwise Relay',true)
  if visible then
    I.Text(ctx,profile.project_name or 'No Wwise project linked')
    I.BeginDisabled(ctx,s.busy or s.working or not win or not w.connected)
    local changed,enabled=I.Checkbox(ctx,'Update after render',s.enabled)
    if changed then
      s.startup_arm=false
      if enabled then schedule(enable) else fs:close_monitor();s.enabled=false;s.detector:cancel();s.pending={};s.job=nil;s.status='Updates paused';s.detail='Enable to follow future renders.' end
    end
    I.EndDisabled(ctx)
    if s.working and I.Button(ctx,'Stop waiting') then
      s.task=nil;s.working=false;w.connected=false;s.job=nil;s.connected_project=nil;s.auto_connect=false
      s.connection_status='Auto-connect paused';s.connection_detail='Use Resume auto-connect in Setup when ready.'
      pause('Stopped waiting. A replacement or conversion already requested may have occurred. Check Wwise before reconnecting or retrying.')
    end
    local connection=w.connected and ('Connected · '..platform_name()) or s.connection_status
    if not w.connected and s.auto_connect and not s.working then
      connection=connection..' · retry in '..math.max(0,math.ceil(s.next_connection-r.time_precise()))..'s'
    end
    I.TextColored(ctx,muted,connection..'  |  v'..C.VERSION)
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
  if fs.heartbeat then fs:heartbeat() end
  if not s.task then s.task=coroutine.create(tick) end
  frame_deadline=r.time_precise()+0.004
  local ok,err=coroutine.resume(s.task)
  if not ok then
    s.task=nil;s.working=false;w.connected=false;s.job=nil;pause(err)
  elseif coroutine.status(s.task)=='dead' then s.task=nil;s.working=false
  else s.working=true end
  local ok,open=pcall(ui)
  if not ok then r.MB(tostring(open),'Wwise Relay — UI error',0);return end
  if open then r.defer(loop) end
end
loop()
