local C=require('relay.core')
local W=require('relay.wwise')
local F=require('relay.files')
local total=0
local function test(name,fn) local ok,err=pcall(fn);assert(ok,name..': '..tostring(err));total=total+1;print('PASS '..name) end
local function raises(fn,part) local ok,err=pcall(fn);assert(not ok,'Expected rejection');if part then assert(tostring(err):find(part,1,true),tostring(err)) end end
local id='{11111111-1111-1111-1111-111111111111}'
local sid='{22222222-2222-2222-2222-222222222222}'
local cid='{33333333-3333-3333-3333-333333333333}'
local pid='{44444444-4444-4444-4444-444444444444}'
local link={render='D:\\Renders\\fire.wav',original='D:\\Game\\Originals\\SFX\\fire.wav',source_id=id,sound_id=sid,container_id=cid,project_id=pid,project_path='D:\\Game\\Game.wproj'}
local function source()return {id=id,type='AudioFileSource',original=link.original,parent_id=sid,language='SFX'} end
test('JSON round trip preserves Windows paths and Unicode',function()
 local v={path="D:\\Audio\\Jeff's $mix`\\火.wav",notify=false,port=8080,links=C.array({{id=id}})}
 local back=C.decode(C.json(v));assert(back.path==v.path and back.notify==false and back.links[1].id==id)
end)
test('empty JSON arrays stay arrays',function()assert(C.json(C.decode('{"links":[]}'))=='{"links":[]}')end)
test('JSON cannot execute Lua',function()raises(function()C.decode('os.execute("bad")')end)end)
test('trailing JSON is rejected',function()raises(function()C.decode('{} return {}')end)end)
test('duplicate JSON keys are rejected',function()raises(function()C.decode('{"a":1,"a":2}')end)end)
test('Unicode surrogate pair is decoded',function()assert(C.decode('"\\uD83D\\uDE00"')=='😀')end)
test('unfinished JSON is rejected',function()raises(function()C.decode('{"a":')end)end)
test('real render report finds exact paths',function()
 local files=C.render_files('FILE:D:\\Renders\\fire.wav;PEAK:-1.4;RMS:-16;FILE:D:\\Renders\\tail.wav;PEAK:-4;')
 assert(#files==2 and files[2]=='D:\\Renders\\tail.wav')
end)
test('empty or cancelled report does not produce candidates',function()assert(#C.render_files('')==0)end)
test('non-WAV and relative paths are excluded',function()assert(#C.render_files('FILE:x.wav;FILE:D:\\x.mp3;FILE:D:\\x.wav;')==1)end)
test('render path deduplication is case insensitive',function()assert(#C.render_files('FILE:D:\\x.wav;FILE:d:/X.wav;')==1)end)
test('valid existing link is accepted',function()assert(C.validate_link(link,source(),{source()},pid,link.project_path))end)
test('wrong project GUID is rejected',function()raises(function()C.validate_link(link,source(),{source()},id,link.project_path)end,'Wrong Wwise project')end)
test('same named project in another location is rejected',function()raises(function()C.validate_link(link,source(),{source()},pid,'E:\\Game.wproj')end)end)
test('deleted source is rejected',function()raises(function()C.validate_link(link,nil,{},pid,link.project_path)end)end)
test('source moved under another sound is rejected',function()local s=source();s.parent_id=cid;raises(function()C.validate_link(link,s,{s},pid,link.project_path)end)end)
test('source path changed is rejected',function()local s=source();s.original='D:\\Else.wav';raises(function()C.validate_link(link,s,{s},pid,link.project_path)end)end)
test('shared WAV owned by another source is rejected',function()local other=source();other.id=cid;raises(function()C.validate_link(link,source(),{source(),other},pid,link.project_path)end,'shared')end)
test('localized audio cannot enter SFX update path',function()local s=source();s.language='English(US)';raises(function()C.validate_link(link,s,{s},pid,link.project_path)end)end)
test('unknown render path has no destination fallback',function()assert(C.index_links({link})['d:\\renders\\new.wav']==nil)end)
test('duplicate render mappings reject the profile',function()raises(function()C.index_links({link,link})end)end)
test('invalid GUID rejects the profile',function()local t={};for k,v in pairs(link)do t[k]=v end;t.source_id='name';raises(function()C.index_links({t})end)end)
test('arming never replays existing render files',function()local d=C.detector();d:baseline({{path=link.render,ok=true,stamp='1'}});d:observe({{path=link.render,ok=true,stamp='1'}},10);assert(not d:take(20))end)
test('changed render waits for a quiet interval',function()local d=C.detector();d:baseline({{path=link.render,ok=true,stamp='1'}});d:observe({{path=link.render,ok=true,stamp='2'}},10);assert(not d:take(11));assert(#d:take(12)==1)end)
test('re-render replaces pending candidate instead of duplicating',function()local d=C.detector();d:observe({{path=link.render,ok=true,stamp='2'}},10);d:observe({{path=link.render,ok=true,stamp='3'}},11);local p=d:take(13);assert(#p==1 and p[1].stamp=='3');assert(not d:take(14))end)
test('invalid or incomplete WAV never queues',function()local d=C.detector();d:observe({{path=link.render,ok=false}},10);assert(not d:take(30))end)
test('cancel clears pending work',function()local d=C.detector();d:observe({{path=link.render,ok=true,stamp='1'}},10);d:cancel();assert(not d:take(30))end)
test('conversion warnings do not become success',function()assert(not C.conversion_status({{severity='Warning',message='Missing codec'}}))end)
test('missing conversion report fails',function()assert(not C.conversion_status(nil))end)
test('clean conversion report succeeds',function()assert(C.conversion_status({}))end)
test('object creation is denied before any WAAPI request',function()raises(function()W.new({}):call('ak.wwise.core.object.create',{})end,'not permitted')end)
test('audio import is denied before any WAAPI request',function()raises(function()W.new({}):call('ak.wwise.core.audio.import',{})end,'not permitted')end)
test('project save and delete are not available',function()raises(function()W.new({}):call('ak.wwise.core.project.save',{})end);raises(function()W.new({}):call('ak.wwise.core.object.delete',{})end)end)
test('arbitrary Wwise UI commands are denied',function()raises(function()W.new({}):call('ak.wwise.ui.commands.execute',{command='Delete'})end,'navigation')end)
test('broad conversion is denied',function()raises(function()W.new({}):call('ak.wwise.core.audio.convert',{objects={id,sid},platforms={'Windows'},languages={'SFX'}})end)end)
test('encoded PowerShell bootstrap is UTF16 base64',function()assert(F.encoded('abc')=='YQBiAGMA')end)
print(('Passed %d Lua tests'):format(total))
return total
