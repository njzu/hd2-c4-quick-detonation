-- Uses the upstream synthetic registries, never a game process or native action.
local fixture=dofile('tests/contact_fixture.lua')
local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local function setup()
    local s=fixture()
    local code='local D,C=...;local GuardSpans=dofile("src/GuardSpans.lua");'..READER_SOURCE
    local reader=assert(loadstring(code))(s.D,s.symbols)
    local scope={owner=s.owner,root=s.root,weapon=s.api.read(s.waddr,24),weapon_id=s.wid,
        identity='synthetic-world-weapon',same=function()return true end}
    return s,reader,scope
end
do
    local s,r,c=setup();s.add(201);s.add(202,{foreign=true});s.add(203,{owned=false});s.add(204,{requested=true})
    local out=r.capture(s.api,s.game,s.base,c)
    check(#out.all==2 and #out.eligible==1 and out.eligible[1].id==201,'only same weapon owned and non-requested C4 eligible')
    check(out.same(),'fresh complete guards')
    local last=s.charges[1];s.put(last.flag,'\1')
    check(not out.same(),'requested mutation invalidates capture')
    check(#s.effects==0,'reader has no explosion effects')
end
do
    local s,r,c=setup();s.add(1);c.root=c.root+8
    check(not pcall(r.capture,s.api,s.game,s.base,c),'world mismatch rejected')
end
do
    local s,r,c=setup();s.add(1);c.weapon=string.rep('x',24)
    check(not pcall(r.capture,s.api,s.game,s.base,c),'weapon generation mismatch rejected')
end
do
    local s,r,c=setup();s.u32(s.remote+0x10,129)
    check(not pcall(r.capture,s.api,s.game,s.base,c),'registry budget enforced before scanning')
end
do
    local s,r,c=setup();s.add(1);s.put(s.charges[1].flag,'\2')
    check(not pcall(r.capture,s.api,s.game,s.base,c),'unknown network state rejected')
end
return checks
