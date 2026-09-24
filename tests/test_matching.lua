-- Test the real Wwise resolver/verification code against a read-only WAAPI fixture.
local C=require('relay.core')
local W=require('relay.wwise')
local total=0
local function test(name,fn)local ok,err=pcall(fn);assert(ok,name..': '..tostring(err));total=total+1;print('PASS '..name)end
local function guid(n)return ('{%08d-1111-1111-1111-111111111111}'):format(n)end
local function fixture()
 local profile={project_id=guid(1),project_path='D:\\Game\\game.wproj',platform=guid(2)}
 local sound={id=guid(3),name='Explosion_01',type='Sound',path='\\Actor-Mixer Hierarchy\\Container\\Explosion_01',parent_id=guid(4)}
 local source={id=guid(5),type='AudioFileSource',parent_id=sound.id,original='D:\\Game\\Originals\\SFX\\old_original_name.wav'}
 local state={project={id=profile.project_id,file=profile.project_path},sounds={sound},sources={source},active=source.id,active_calls=0}
 local w=W.new({});w.originals='D:\\Game\\Originals'
 function w:project()return state.project end
 function w:objects(from)
   if from.ofType then
     local kind=from.ofType[1]
     if kind=='Platform' then return {{id=profile.platform,name='Windows'}} end
     if kind=='Sound' then return state.sounds end
     if kind=='AudioFileSource' then return state.sources end
   elseif from.id and from.id[1]==guid(4) then return {{id=guid(4),type='RandomSequenceContainer',path='\\Actor-Mixer Hierarchy\\Container'}} end
   error('Unexpected object query')
 end
 function w:call(uri,args,options,read)
   assert(uri=='ak.wwise.core.object.get','Resolver attempted a non-read operation')
   assert(args.from.id[1]==sound.id)
   assert(options['return'][1]=='activeSource' and options.platform==profile.platform)
   state.active_calls=state.active_calls+1
   local Q={get=function(p,k)return p and p[k]end,text=function(p,k)return p and p[k] or ''end}
   function Q.list(p,k,reader)local out={};for _,x in ipairs(p[k])do out[#out+1]=reader(x)end;return out end
   return read(Q,{['return']={{activeSource={id=state.active}}}})
 end
 return w,profile,state,sound,source
end
local path='C:\\Renders\\Explosion_01.wav'
test('automatic resolver uses the matched Sound active source, not the original filename',function()
 local w,p,s,sound,source=fixture();local link=assert(w:match(path,p,w:catalog(p)))
 assert(link.sound_id==sound.id and link.source_id==source.id and link.original==source.original and link.container_id==guid(4))
 assert(w:verify(link,p))
end)
test('missing sound is skipped without looking up a source',function()
 local w,p,s=fixture();s.sounds={};local link,reason=w:match(path,p,w:catalog(p));assert(not link and reason:find('No existing',1,true) and s.active_calls==0)
end)
test('ambiguous sounds are skipped before source lookup',function()
 local w,p,s,sound=fixture();local other=C.decode(C.json(sound));other.id=guid(6);s.sounds[2]=other
 local link,reason=w:match(path,p,w:catalog(p));assert(not link and reason:find('More than one',1,true) and s.active_calls==0)
end)
test('plugin or absent active source cannot be auto-matched',function()
 local w,p,s=fixture();s.active=guid(9);local link,reason=w:match(path,p,w:catalog(p));assert(not link and reason:find('no active file-based',1,true))
end)
test('the selected platform active source is used even when a sound has multiple sources',function()
 local w,p,s,sound,source=fixture();local other=C.decode(C.json(source));other.id=guid(6);other.original='D:\\Game\\Originals\\SFX\\alternate.wav';s.sources[2]=other;s.active=other.id
 local link=assert(w:match(path,p,w:catalog(p)));assert(link.source_id==other.id and link.original==other.original)
end)
test('shared originals are skipped automatically',function()
 local w,p,s,sound,source=fixture();local other=C.decode(C.json(source));other.id=guid(6);other.parent_id=guid(9);s.sources[2]=other
 local link,reason=w:match(path,p,w:catalog(p));assert(not link and reason:find('shared',1,true))
end)
test('localized audio is skipped automatically',function()
 local w,p,s,sound,source=fixture();source.original='D:\\Game\\Originals\\Voices\\English(US)\\Explosion_01.wav'
 local link,reason=w:match(path,p,w:catalog(p));assert(not link and reason:find('Only SFX',1,true))
end)
test('wrong project is rejected before creating a match catalog',function()
 local w,p,s=fixture();s.project.file='D:\\Other\\game.wproj';assert(not pcall(function()w:catalog(p)end))
end)
test('a duplicate introduced after matching prevents replacement verification',function()
 local w,p,s,sound=fixture();local link=assert(w:match(path,p,w:catalog(p)));local other=C.decode(C.json(sound));other.id=guid(6);s.sounds[2]=other
 assert(not pcall(function()w:verify(link,p)end))
end)
test('a renamed sound cannot reuse an earlier match',function()
 local w,p,s,sound=fixture();local link=assert(w:match(path,p,w:catalog(p)));sound.name='Renamed';assert(not pcall(function()w:verify(link,p)end))
end)
test('active source changes invalidate the automatic match',function()
 local w,p,s=fixture();local link=assert(w:match(path,p,w:catalog(p)));s.active=guid(6);assert(not pcall(function()w:verify(link,p)end))
end)
test('source path changes invalidate the automatic match',function()
 local w,p,s,sound,source=fixture();local link=assert(w:match(path,p,w:catalog(p)));source.original='D:\\Game\\Originals\\SFX\\changed.wav';assert(not pcall(function()w:verify(link,p)end))
end)
test('rendering directly into the matched original is rejected',function()
 local w,p,s,sound,source=fixture();source.original='D:\\Game\\Originals\\SFX\\Explosion_01.wav'
 local link,why=w:match(source.original,p,w:catalog(p));assert(not link and why:find('Render and original paths must differ',1,true))
end)
return total
