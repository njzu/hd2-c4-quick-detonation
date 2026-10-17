local n=0
local function check(v,why)assert(v,why);n=n+1 end
local function ctx(extra)
    local c={identity='world:a',scope=true,aim_owned=true,active=false,ability=0}
    for k,v in pairs(extra or {})do c[k]=v end;return c
end
local released={left=false,right=false}
local right={left=false,right=true,right_edge=true}
local function fresh()
    local r=Requests.new(function()end);local c=ctx()
    r.observe(c,0,1,'before');r.input(c,released,0,1)
    r.observe(c,.01,1,'after');r.input(c,released,.01,1)
    return r
end
local function targets(...)local all={};for _,id in ipairs({...})do all[#all+1]={identity=id}end;return {eligible=all}end
do
    local r=fresh();r.input(ctx(),right,.1,2)
    check(r.can_read() and r.targets(targets('old'),10),'idle remote target accepted')
    local p=r.submitted();check(p.id==1 and not r.pending,'consume before native')
    check(not r.can_read(),'no automatic retry or 520 fallback')
    r.input(ctx(),{left=false,right=true},.2,3);check(not r.pending,'held right does not repeat')
    r.input(ctx(),right,.3,4);check(r.pending.id==2,'explicit new edge is a new request')
end
do
    local r=fresh();r.baseline({old=true},2)
    local t=ctx{active=true,ability=521,clock=0,released=false}
    r.observe(t,.1,2,'after');r.input(t,right,.1,2)
    check(not r.can_read(),'wait until release')
    t.clock=.2;t.released=true;r.observe(t,.3,3,'after')
    check(r.can_read(),'released while 521 still active')
    check(not r.targets(targets('old'),20),'old C4 does not prove new release association')
    check(r.targets(targets('old','new'),20),'new owned identity proves association')
    r.observe(ctx{avatar_reload=true},.4,4,'after')
    check(r.throw.released and r.pending~=nil,'release latched across 521 end and normal reload')
    check(r.targets(targets('new'),20),'normal reload does not require another click')
end
do
    local r=fresh();local both={left=true,right=true,left_edge=true,right_edge=true}
    r.input(ctx(),both,.1,2);r.baseline({old=true},2)
    check(not r.can_read(),'same-frame left has priority')
    local t=ctx{active=true,ability=521,clock=0,released=false}
    r.observe(t,.11,2,'after')
    check(r.pending and r.pending.epoch==r.epoch,'competing pending binds actual new throw')
    t.clock=.2;t.released=true;r.observe(t,.3,3,'after')
    r.input(t,{left=true,right=true},.3,3)
    check(r.can_read() and r.targets(targets('new'),10),'held left does not block after same throw released')
end
do
    local r=fresh();r.input(ctx(),{left=true,right=true,left_edge=true,right_edge=true},.1,2)
    r.observe(ctx(),.2,3,'after');check(not r.pending,'unaccepted left cannot attach to a future throw')
end
do
    local r=fresh();r.baseline({},2)
    local t=ctx{active=true,ability=521,clock=.01,released=false}
    r.observe(t,.1,2,'after');r.input(t,right,.1,2)
    t.clock=0;r.observe(t,.2,3,'after');check(not r.pending,'clock reset creates new epoch and drops stale pending')
end
do
    local r=fresh();r.input(ctx(),right,.1,2);check(not r.targets(targets(),10) and not r.pending,'no target never attaches to next throw')
    r.input(ctx(),right,.2,3);r.observe(ctx{identity='world:b'},.3,4,'before')
    check(not r.pending and not r.armed,'new world discards pending and requires baseline')
end
do
    local r=fresh();r.input(ctx(),right,.1,2);r.observe(ctx(),1.61,100,'after')
    check(not r.pending,'TTL is from right edge, never reset by reload')
    r.input(ctx(),right,2,101);r.observe(nil,2.1,102,'after')
    check(not r.pending,'scope/UI loss cancels')
end
do
    local r=fresh();r.input(ctx(),right,.1,2);r.observe(ctx{veto='UNCLASSIFIED_AVATAR_FLAG_14'},.2,3,'after')
    check(not r.pending and r.identity=='world:a','unknown veto cancels request without invalidating identity')
end
do
    local r=fresh();r.input(ctx(),right,.1,2)
    check(not r.targets(targets('new'),4097) and not r.pending,'hard per-request read budget')
    r.fail('call_result_uncertain');r.observe(ctx(),.2,3,'after');r.input(ctx(),right,.2,3)
    check(not r.pending and r.fault,'fault is latched with no retry')
end
do
    local r=fresh();r.input(ctx(),right,.1,2)
    check(r.commit_ready(1.59),'fresh request passes final TTL check')
    check(not r.commit_ready(1.61) and not r.pending,'long target/guard work cannot dispatch expired request')
end
return n
