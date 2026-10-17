local fixture=dofile('tests/contact_fixture.lua')
local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local s=fixture();local ffi=require('ffi')
local R=dofile('private/tests/mock_symbols.lua');local D=s.D
local registry=s.allocate();local states=s.allocate();local map=s.allocate()
s.map(s.ability+0x18,map,{{s.wid,1},{s.aid,2}})
s.ptr(s.ability+0x30,registry);s.ptr(registry+8,s.waddr);s.ptr(registry+16,s.eaddr)
s.ptr(s.ability+0x38,states);s.zero(states+0xe0,0xe0);s.zero(states+2*0xe0,0xe0)
s.ability_state=states+0xe0;local avatar=states+2*0xe0
s.u32(avatar,2827);s.put(avatar+16,'\1')
-- Page-granular memory model makes grouped revalidation comparable to real committed pages.
s.fill=function(at)return s.pages[math.floor(at/4096)] and '\0' or nil end
local code='local R,D,C=...;local AvatarFlags=dofile("src/AvatarFlags.lua");'..FAST_SOURCE
local reader=assert(loadstring(code))(R,D,s.symbols)
local row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(cap and cap.scope and not cap.veto,'known avatar reload activity does not invalidate scope')
check(row.avatar_ability_active and row.avatar_ability_id==2827,'avatar activity observed without ID whitelist')
check(cap.mode.value==0 and cap.operable,'DEPLOY instance and current operability')
check(cap.avatar_active,'busy avatar remains remote-capable')
check(reader.validate(s.api,s.game,s.base,cap),'fresh C4 descriptor validation')
s.u32(s.ability_state,521);s.put(s.ability_state+16,'\1')
s.put(s.ability_state+8,ffi.string(ffi.new('float[1]',.2),4))
row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(cap and cap.active and cap.released,'release phase observed while avatar reload active')
s.put(s.avatar_flags+math.floor(14/8),string.char(64))
row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(cap and cap.scope and cap.veto=='UNCLASSIFIED_AVATAR_FLAG_14','unknown native flag is explicit veto, not an invented reload whitelist')
s.put(s.avatar_flags+1,'\0');s.put(s.ability_state+16,'\0')
local cache=dofile('src/SnapshotCache.lua').new(function()return reader.snapshot(s.api,s.game,s.base)end)
cache.begin_phase();local a,b,c=cache.snapshot();cache.end_phase()
local before=s.read_calls;cache.begin_phase();cache.snapshot();cache.end_phase();local cached=s.read_calls-before
before=s.read_calls;reader.snapshot(s.api,s.game,s.base);local full=s.read_calls-before
check(cached<full,'idle cache revalidates fresh bytes using fewer reads than a full walk')
check(c.same(),'cache capability rechecks current bytes')
check(cache.stats==nil,'Release cache has no diagnostic counters')
s.put(s.ability_state+8,ffi.string(ffi.new('float[1]',.3),4))
cache.begin_phase();cache.snapshot();cache.end_phase()
check(not c.same(),'dynamic ability bytes invalidate retained capability')
s.put(s.ability_state+8,ffi.string(ffi.new('float[1]',.2),4))

s.put(s.avatar_flags+13,'\128');row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(cap and cap.scope and not cap.operable and not reader.live_operable(s.api,cap),'bit111 blocks while slot3 still selected')
s.put(s.avatar_flags+13,'\0');row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(reader.live_operable(s.api,cap),'fresh operability after clear')
s.u32(0x4b000000+16,0x100);row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(cap and cap.mode.value==1 and reader.validate(s.api,s.game,s.base,cap,true),'mode1 qualified for instance normalization')
check(not pcall(reader.validate,s.api,s.game,s.base,cap,false),'mode1 cannot acquire Aim')
s.u32(0x4b000000+16,0x200);row,why,cap=reader.snapshot(s.api,s.game,s.base)
check(not cap,'unknown mode rejected')
s.u32(0x4b000000+16,0);s.put(avatar+16,'\0');row,why,cap=reader.snapshot(s.api,s.game,s.base)
cap.native_identity=cap.identity
local idle=assert(loadstring('local R,D,C=...;'..IDLE_SOURCE))(R,D,s.symbols)
check(idle.capture(s.api,s.game,s.base,cap),'native strict-idle eligibility')
s.put(s.fire_state,'\1');check(not idle.capture(s.api,s.game,s.base,cap),'Fire latch excludes idle520')
s.put(s.fire_state,'\0');s.u32(s.blocker_state+0x19c,2)
check(not idle.capture(s.api,s.game,s.base,cap),'native blocker excludes idle520')
s.u32(s.blocker_state+0x19c,0);s.u32(s.exclusion_state,4)
check(not idle.capture(s.api,s.game,s.base,cap),'native exclusions exclude idle520')
s.u32(s.exclusion_state,0);s.put(s.waddr,'x');check(not c.same(),'stale entity generation fails fresh validation')

return string.format('{"assertions":%d,"full_fast_walk_reads":%d,"idle_cache_validation_reads":%d}',checks,full,cached)
