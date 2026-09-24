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
local profile={version=1,links=C.array(),port=8080,platform='',notify=true}
local saved=r.GetExtState(C.SECTION,key)
local startup_error
if saved~='' then
  local ok,p=pcall(C.decode,saved)
  if ok and type(p)=='table' and p.version==1 and type(p.links)=='table' and p.port and p.platform then
    local valid,err=pcall(C.index_links,p.links)
    if valid then profile=p else startup_error='Saved links need attention: '..tostring(err) end
  else startup_error='Saved profile could not be loaded. Set up the project again.' end
end
local w=W.new(r,profile.port)
local fs=F.new(r,worker)
local s={enabled=false,status='Ready to set up',detail='Connect to Wwise and link your existing audio.',error=startup_error,
  results={},containers={},details=false,detector=C.detector(),job=nil,next_probe=0,last_stats='',pending={},busy=false,
  render_path='',tab='Setup',toast='',toast_until=0,selected_container=1,link_candidate=nil,baseline={},last_files={}}
local heartbeat_key='instance:'..project_guid
local now=r.time_precise()
local prior=tonumber(r.GetExtState(C.SECTION,heartbeat_key)) or 0
if prior>0 and math.abs(now-prior)<4 then r.MB('Wwise Relay is already running for this REAPER project.','Wwise Relay',0);return end
r.SetExtState(C.SECTION,heartbeat_key,tostring(now),false)
local function save() r.SetExtState(C.SECTION,key,C.json(profile),true) end
local function toast(text) s.toast=text;s.toast_until=r.time_precise()+6 end
local function pause(message)
  s.enabled=false;s.detector:cancel();s.pending={};s.busy=false;s.error=tostring(message);s.status='Updates paused';s.detail='Resolve the issue, then enable updates again.'
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
  s.connected_project=p;s.error=nil;s.status='Connected';s.detail='Enable updates when your audio links are ready.'
  s.info=info
end
local function pin()
  assert(s.connected_project,'Connect to Wwise first')
  current_project()
  assert(#profile.links==0 or matched_project(s.connected_project),'Remove this profile’s links before choosing another Wwise project')
  profile.project_id=s.connected_project.id;profile.project_path=s.connected_project.file;profile.project_name=s.connected_project.name
  if profile.platform=='' then
    for _,p in ipairs(w.platforms) do if p.name=='Windows' then profile.platform=p.id end end
    if profile.platform=='' then profile.platform=w.platforms[1].id end
  end
  save();toast('Project pinned. Link an existing audio source next.')
end
local function platform_name()
  for _,p in ipairs(w.platforms or {}) do if p.id==profile.platform then return p.name end end
  return profile.platform_name or 'Choose platform'
end
local function prepare_link()
  s.enabled=false;s.detector:cancel();s.pending={};current_project()
  assert(profile.project_id,'Connect and pin the Wwise project in Setup first')
  assert(matched_project(w:project()),'The pinned Wwise project is not open')
  assert(C.absolute(s.render_path) and s.render_path:lower():match('%.wav$'),'Choose an existing rendered WAV')
  assert(not s.render_path:find(';',1,true),'Semicolons in filenames are not supported by REAPER render reports')
  local source,sound,container,all=w:selected_source()
  local link={render=s.render_path,source_id=source.id,sound_id=sound.id,container_id=container.id,
    container_path=container.path,source_path=source.path,original=source.original,project_id=profile.project_id,project_path=profile.project_path}
  C.validate_link(link,source,all,profile.project_id,profile.project_path)
  for _,l in ipairs(profile.links) do
    assert(C.key(l.render)==C.key(link.render) or l.source_id~=link.source_id,'That Wwise source already has another render file linked')
  end
  local checks=fs:inspect({link.render,link.original},true)
  assert(#checks==2 and checks[1].ok and checks[2].ok,((checks[1] or {}).error or (checks[2] or {}).error or 'Could not read both WAVs'))
  assert(checks[1].channels==checks[2].channels,'Rendered WAV and Wwise original must have the same channel count')
  link.destination_sha=checks[2].sha;link.render_stamp=checks[1].stamp
  s.link_candidate=link;s.error=nil
end
local function accept_link()
  local link=s.link_candidate;assert(link,'No link to save')
  local found=false
  for i,l in ipairs(profile.links) do if C.key(l.render)==C.key(link.render) then profile.links[i]=link;found=true end end
  if not found then profile.links[#profile.links+1]=link end
  C.index_links(profile.links);save();s.link_candidate=nil;toast('Existing source linked. No audio was changed.')
end
local function enable()
  current_project();assert(win,'Live updates require Windows');assert(w.connected,'Connect to Wwise first')
  assert(profile.project_id and #profile.links>0,'Pin your project and add at least one existing audio link')
  assert(matched_project(w:project()),'Wrong Wwise project')
  local valid=false;for _,p in ipairs(w.platforms) do if p.id==profile.platform then valid=true end end
  assert(valid,'Select a valid conversion platform')
  local paths={};for _,l in ipairs(profile.links) do paths[#paths+1]=l.render end
  -- Baseline every approved render path, not a recursive watch of a directory.
  s.detector=C.detector();local checks=fs:inspect(paths)
  for _,v in ipairs(checks) do assert(v.ok,v.path..': '..(v.error or 'Cannot inspect WAV')) end
  s.detector:baseline(checks)
  s.last_stats=stats();s.last_files=C.render_files(s.last_stats)
  -- Include old unlinked report entries so enabling never replays history.
  if #s.last_files>0 then s.detector:baseline(fs:inspect(s.last_files)) end
  s.pending={};s.job=nil;s.enabled=true;s.error=nil;s.status='Waiting for render';s.detail='Render through NVK as usual.';s.next_probe=r.time_precise()+1.5
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
local function process_one()
  local item=table.remove(s.pending,1);if not item then return end
  current_project()
  local link=C.index_links(profile.links)[C.key(item.path)]
  local row={path=item.path,state='Skipped',message='No approved link; no Wwise audio changed.'};s.results[#s.results+1]=row
  if link then
    row.link=link;row.state='Failed';s.status='Updating '..C.basename(item.path);s.detail='Verifying the existing source...'
    local ok,err=pcall(function()
      w:verify(link,profile)
      local previous_sha=link.destination_sha
      local replaced=fs:replace(link,item)
      row.replaced=true;row.state='Conversion failed';link.destination_sha=replaced.sha;link.pending_conversion=true;save()
      -- Verify identity again after replacement; never convert a new/moved object.
      w:verify(link,profile)
      local converted=w:convert(link,profile.platform)
      fs:artifact(converted,replaced.stamp,previous_sha==replaced.sha)
      row.state='Converted';row.message='Original bytes verified; Wwise reported no conversion messages; converted media is current.'
      link.pending_conversion=nil;save()
      local have=false;for _,v in ipairs(s.containers) do if v.id==link.container_id then have=true end end
      if not have then s.containers[#s.containers+1]={id=link.container_id,path=link.container_path} end
    end)
    if not ok then
      row.message=tostring(err);s.error=row.message;s.enabled=false
      for _,remaining in ipairs(s.pending) do
        s.results[#s.results+1]={path=remaining.path,state='Not processed',message='Paused after the preceding failure.',link=C.index_links(profile.links)[C.key(remaining.path)]}
      end
      s.pending={}
    end
  end
  if #s.pending==0 then s.busy=false;summary() end
end
local function retry_failed()
  current_project();assert(w.connected,'Connect first')
  local paths={};for _,v in ipairs(s.results) do if v.link and v.state~='Converted' then paths[#paths+1]=v.link.render end end
  assert(#paths>0,'No linked failures to retry')
  local items=fs:inspect(paths)
  for _,v in ipairs(items) do assert(v.ok,v.error or 'Cannot read rendered file') end
  s.pending=items;s.results={};s.containers={};s.busy=true;s.error=nil;s.tab='Latest render'
end
local function tick()
  local time=r.time_precise();r.SetExtState(C.SECTION,heartbeat_key,tostring(time),false)
  if s.busy then process_one();return end
  if not s.enabled then return end
  current_project()
  local report=stats()
  if report=='' then s.detector:cancel();s.last_stats='';s.last_files={};s.job=nil;return end
  local files=C.render_files(report)
  if #files==0 then return end
  if s.job then
    local items=fs:poll(s.job)
    if items then
      -- A cancelled or replaced render report invalidates an in-flight inspection.
      if report==s.job.report then
        s.detector:observe(items,time)
      end
      s.job=nil
    end
  end
  if not s.job and time>=s.next_probe then
    s.job=fs:begin_inspect(files);s.job.report=report;s.next_probe=time+1.5;s.last_stats=report;s.last_files=files
  end
  local ready=s.detector:take(time)
  if ready then s.tab='Latest render';s.results={};s.containers={};s.selected_container=1;s.pending=ready;s.busy=true;s.error=nil end
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
      text(v.message);I.PopID(ctx)
    end
    button('Retry failed linked files',retry_failed,s.busy or not w.connected)
  end
  if s.error then
    I.Separator(ctx);I.TextColored(ctx,amber,'Attention');text(s.error)
    button('Dismiss message',function()s.error=nil end)
  end
end
local function links_tab()
  I.BeginDisabled(ctx,s.busy)
  text('Select one existing sound/source in Wwise, then choose its rendered WAV here.')
  button('Choose rendered WAV...',function()
    local ok,path=r.GetUserFileNameForRead(s.render_path,'Choose existing REAPER output WAV','.wav')
    if ok then s.render_path=path;s.link_candidate=nil end
  end)
  if s.render_path~='' then text(C.basename(s.render_path)) end
  button('Read selected Wwise source',prepare_link,not w.connected or s.render_path=='')
  if s.link_candidate then
    local l=s.link_candidate;text(l.render..'\n→ '..l.source_path)
    button('Save approved link',accept_link);I.SameLine(ctx);button('Cancel',function()s.link_candidate=nil end)
  end
  I.Separator(ctx)
  for i,l in ipairs(profile.links) do
    I.PushID(ctx,i);text(C.basename(l.render));I.TextColored(ctx,muted,l.source_path)
    button('Unlink',function()s.enabled=false;table.remove(profile.links,i);save()end)
    I.SameLine(ctx);button('Show container',function()w:show(l.container_id,profile)end,not w.connected)
    if l.pending_conversion then I.TextColored(ctx,amber,'Previous replacement still needs conversion') end
    I.Separator(ctx);I.PopID(ctx)
  end
  I.EndDisabled(ctx)
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
      if enabled then guard(enable) else s.enabled=false;s.detector:cancel();s.pending={};s.status='Updates paused';s.detail='Enable to follow future renders.' end
    end
    I.EndDisabled(ctx)
    I.TextColored(ctx,muted,(w.connected and ('Connected · '..platform_name()) or 'Not connected')..'  |  v'..C.VERSION)
    if not win then I.TextColored(ctx,amber,'UI preview — live updates require Windows') end
    if I.BeginTabBar(ctx,'views') then
      for _,t in ipairs({'Latest render','Audio links','Setup'}) do
        local flags=s.tab==t and I.TabItemFlags_SetSelected or 0
        if I.BeginTabItem(ctx,t,nil,flags) then
          if s.tab==t then s.tab=nil end
          if t=='Latest render' then render_tab() elseif t=='Audio links' then links_tab() else setup_tab() end
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
