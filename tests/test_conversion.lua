local C=require('relay.core');local W=require('relay.wwise');local F=require('relay.files')
local total=0
local function test(name,fn)local ok,err=pcall(fn);assert(ok,name..': '..tostring(err));total=total+1;print('PASS '..name)end
local old='{11111111-1111-1111-1111-111111111111}'
local new='{22222222-2222-2222-2222-222222222222}'
local function fixture(hash)
 local requests={};local now=0
 local w=W.new({time_precise=function()now=now+0.1;return now end},8080,{run=function(_,req)
  requests[#requests+1]=req
  if req.action=='refresh' then return {ok=true} end
  if req.uri=='ak.wwise.core.audio.convert' then return {data={errors={}}} end
  return {data={['return']={{id=old,contentHash=hash,convertedWemFilePath='C:\\cache.wem'}}}}
 end})
 function w:verify()return true end
 return w,requests
end
local link={source_id=old,sound_id=old,original='C:\\Game\\Originals\\SFX\\nested\\original.wav'}
local profile={project_id=old,project_path='C:\\Game\\game.wproj',platform=old}
local function complete(fn)
 local co=coroutine.create(fn)
 for _=1,500 do local ok,value=coroutine.resume(co);if not ok then return false,value end;if coroutine.status(co)=='dead' then return true,value end end
 error('Coroutine did not finish')
end
test('source refresh sends only pinned identities and existing path',function()
 local w,requests=fixture(new)
 assert(w:refresh(link,profile,old,true)==new)
 local req=requests[1];assert(req.action=='refresh' and not req.uri and not req.args)
 assert(req.projectId==old and req.projectPath==profile.project_path and req.sourceId==old and req.original==link.original)
end)
test('changed audio with stale Wwise identity pauses before conversion',function()
 local w,requests=fixture(old)
 local ok,why=complete(function()w:refresh(link,profile,old,true)end)
 assert(not ok and why:find('previous audio',1,true))
 for _,req in ipairs(requests) do assert(req.uri~='ak.wwise.core.audio.convert') end
end)
test('same sample data can reuse its verified content identity',function()
 local w=fixture(old);assert(w:refresh(link,profile,old,false)==old)
end)
test('a source that changes during conversion cannot report success',function()
 local w=fixture(new);local ok,why=pcall(function()w:convert(link,old,old)end)
 assert(not ok and why:find('changed during conversion',1,true))
end)
test('conversion requires refreshed content identity',function()
 local w,requests=fixture(old);assert(not pcall(function()w:convert(link,old)end));assert(#requests==0)
end)
test('old cache timestamps are valid only when the embedded content hash matches',function()
 local f=setmetatable({run=function()return {length=100,ticks='1',contentHash=old}end},F)
 assert(f:artifact('C:\\cached.wem',old))
 assert(not pcall(function()f:artifact('C:\\cached.wem',new)end))
end)
return total
