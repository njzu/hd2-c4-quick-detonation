local fixture=dofile('tests/contact_fixture.lua')
local R=dofile('private/tests/mock_symbols.lua')
local checks=0
local function check(v,name)assert(v,name);checks=checks+1 end
local function create(source)
    local s=fixture();local D=s.D
    s.fill=function(at)return s.pages[math.floor(at/4096)] and '\0' or nil end
    dofile('tests/aim_fixture.lua')(s,R,D,s.base)
    local spans=dofile('src/GuardSpans.lua')
    local input=assert(loadstring('local R,D,GuardSpans=...\n'..INPUT_SOURCE))(R,D,spans)
    local module=assert(loadstring('local D,AimInputState=...\n'..source))(D,input)
    local cap={identity='same_world_and_full_entity',same=function()return true end}
    local native={inhibit=function(owner,action)s.native.input_inhibit(owner,action,1,-1)end,
        unblock=s.native.input_unblock}
    local aim=module.new(s.api,s.game,s.base,native,function()end,function()return true end,function()end,function()end,function()return 0 end)
    check(aim.sync(cap,true,true),'fresh acquisition')
    local start=s.read_calls
    for i=1,120 do assert(aim.sync(cap,true,true),'held lease remains valid')end
    check(aim.lease~=nil,'held lease survives 120 validation phases')
    return s,aim,cap,(s.read_calls-start)/120
end
local old,oldaim,oldcap,oldreads=create(OLD_SOURCE)
local s,aim,cap,reads=create(NEW_SOURCE)
check(reads<oldreads,'Aim hints reduce actual held-path API reads')
check(aim.stats.reused>=119 and aim.stats.rebuilt>=2,'held path counts cache hits and rebuilds')
local n=s.read_calls;check(aim.valid(cap),'commit validation succeeds with current mask')
check(s.read_calls>n and aim.stats.fresh_reads>=2,'valid bypasses hints and reads fresh memory')
s.put(s.aim_state,'\1');local rebuilds=aim.stats.rebuilt
check(aim.sync(cap,true,false) and aim.stats.rebuilt>rebuilds,'changed held-state byte invalidates cached input')
s.set_mask(2);check(not aim.valid(cap),'foreign mask blocks commit')
local unblocks=s.unblock_calls;aim.stop()
check(s.unblock_calls==unblocks and not aim.lease,'foreign mask is never restored as ours')
s.set_mask(0);s.put(s.aim_state,'\0');check(aim.sync(cap,true,true),'reacquire after explicit released baseline')
n=s.read_calls;aim.stop();check(s.unblock_calls==unblocks+1 and s.read_calls>n,'stop is fresh and releases own mask')
local held=aim.stats.held_reads
s.ptr(s.game+R.global_input_owner,0)
check(not pcall(aim.sync,cap,true,true),'changed input owner cannot reuse stale cache')
check(aim.stats.held_reads==held,'unreadable owner never counts as a successful reuse')
return string.format('{"assertions":%d,"m12_held_reads_per_phase":%.6f,"m13_held_reads_per_phase":%.6f,"held_reuses":%d}',checks,oldreads,reads,aim.stats.reused)
