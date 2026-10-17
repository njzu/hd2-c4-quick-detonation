local checks=0
local function check(v,name)assert(v,name);checks=checks+1 end
local function setup(options)
    options=options or {}
    local f={t=0,left=false,right=false,world='w',scope=true,ui=false,focus=true,active=false,ability=0,
        clock=0,release=false,avatar=false,standing=true,transition=false,mode=options.mode or 0,
        gate=false,remotes=0,starts=0,unblocks=0,writes=0,targets={},events={},same=true,captures=0}
    local e=setmetatable({},{__index=_G});e._G=e
    local function word()return string.char(0,f.mode,0,0)end
    local api={time=function()return f.t end,memo_reset=function()end,memo_begin=function()end,memo_end=function()end,
        module=function()return 1000 end,read=function()return word()end}
    local symbols={fn_input_inhibit=20,fn_input_unblock=30,contact_remote_owner=10,fn_start=40,
        fn_detonate_lifecycle=50,contact_remote_lifecycle=50}
    local fields={input_aim_action=123,input_aim_code=131080,input_inhibit_capacity=8}
    local casts={
        [1010]=function()f.remotes=f.remotes+1;if f.call_error then error('remote_unknown')end end,
        [1020]=function()f.gate=true end,
        [1030]=function()f.gate=false;f.unblocks=f.unblocks+1 end,
        [1040]=function(_,id,ability,network,speed)
            assert(id==11 and ability==520 and network==1 and speed==1)
            f.starts=f.starts+1;if f.start_error then error('start_unknown')end
            if not f.no_start_observed then f.active=true;f.ability=520 end
        end}
    e.require=function(name)
        if name=='ffi' then return {cdef=function()end,load=function()return{c4daily_GetAsyncKeyState=function(k)
            return(k==1 and f.left or k==2 and f.right)and 32768 or 0 end}end,
            cast=function(kind,value)if kind=='void *'then return value end;return assert(casts[value],'unapproved ABI')end}end
        return require(name)
    end
    e.CowboyBingusModLoader={api=1,open_log=function()end}
    e.stingray={Application={main_world=function()return f.world end}}
    e.update=function()if f.hook then f.hook()end;if f.original_error then error('original-sentinel',0)end;return nil,77,nil end
    e.shutdown=function(...)return nil,'shutdown',...end
    local resolved=0
    e.test_modules={
        SessionLog={new=function()return{once=function(k,v)f.events[#f.events+1]={kind=k,fields=v}end,
            event=function(k,v)f.events[#f.events+1]={kind=k,fields=v}end,close=function()end}end},
        Metrics={new=function()assert(DIAG,'Release cannot construct Metrics');return{clock=function()return f.t end,
            stage=function()end,frame=function()end}end},
        WindowsRead=function()return api end,ReadMemo=function()end,
        NativeResolver={new_scan=function()return{release=function()end}end,resolve=function()
            resolved=resolved+1;if resolved==3 and options.no_action then error('optional signature mismatch')end
            return{symbols=symbols,fields=fields,verify=function()end,verifier_for=function()return function()end end}end},
        ContextReader={},SnapshotCache={new=function(fetch)return{snapshot=fetch,begin_phase=function()end,
            end_phase=function()end,invalidate=function()end}end},
        FastReader={validate=function(_,_,_,cap,allow)assert(f.same and(f.mode==0 or allow and f.mode==1))end,
            live_operable=function()return not f.transition,'EQUIPMENT_TRANSITION'end,
            snapshot=function()
                if not f.scope then return{},nil,nil end
                return{},nil,{identity='entity',scope=true,operable=not f.transition,transition=f.transition,
                    owner=8,root=9,weapon='weapon',weapon_id=11,same=function()return f.same end,
                    mode={value=f.mode,word=f.mode*256,bytes=word(),at=100},
                    active=f.active,ability=f.ability,clock=f.clock,released=f.release,
                    avatar_active=f.avatar,standing=f.standing,veto=f.veto}
            end},
        InstanceWrite={new=function()return function()assert(not f.left and not f.right and not f.transition)
            if f.write_error then error('write_unconfirmed')end;f.writes=f.writes+1;f.mode=0;return true end end},
        Idle520={capture=function()if f.final_transition then f.transition=true end
            if f.idle_reject then return nil end;return{manager=2000,same=function()return f.same end}end},
        WindowFocus=function()return function()return f.focus end end,NativeUiGuard={new=function()end},
        GameplayGuard={new=function()return{sample=function()return f.focus and not f.ui end}end},
        AimInputState={read=function()return{owner=8,count=1,held=false,same=function()return f.same end,
            mask={mode=f.gate and 1 or 0,bytes=f.gate and string.rep('\0',24)or'released'}}end},
        RemoteReader={capture=function()
            f.captures=f.captures+1;if f.target_error then error('target_unreadable')end
            local all,eligible,set={},{},{}
            for _,item in ipairs(f.targets)do local c={identity=item.identity,requested=item.requested}
                all[#all+1]=c;set[c.identity]=true;if not c.requested then eligible[#eligible+1]=c end end
            return{manager=2000,all=all,eligible=eligible,set=set,same=function()return f.same end}
        end}}
    if options.old then e.HD2C4RemoteM13={}end
    local run=assert(loadstring(ENTRY));setfenv(run,e);local m=run()
    local function tick()f.t=f.t+.016;return e.update(.016)end
    tick();tick();return f,e,m,tick,run
end
do
    local f,e,m,tick,run=setup();check(m.status=='ready'and f.gate,'released idle acquires Aim')
    f.targets={{identity='old'}};f.right=true;tick()
    check(f.starts==1 and f.remotes==0 and not m.requests.pending,'idle request commits native520 exclusively')
    tick();check(f.starts==1 and f.remotes==0,'active520 transaction cannot replay')
    f.right=false;f.hook=function()f.active=false end;tick();f.hook=nil;tick()
    f.right=true;tick();check(f.starts==2 and f.remotes==0,'new physical edge after finished lifecycle accepted')
    local original=e.update;check(run()==m and e.update==original,'idempotent initialization')
    local function vals(...)check(select('#',...)==3 and select(2,...)==77,'original nil returns preserved')end;vals(tick())
    f.scope=false;f.hook=function()check(not f.gate,'scope loss releases Aim before original')end;tick();f.hook=nil
    local a,b,c=e.shutdown('tail');check(a==nil and b=='shutdown'and c=='tail','shutdown returns preserved')
end
do
    local f,e,m,tick=setup();f.avatar=true;f.targets={{identity='old'}};f.right=true;tick()
    check(f.remotes==1 and f.starts==0 and not m.disabled,'avatar busy uses remote exclusively')
    tick();check(f.remotes==1,'held RMB does not replay busy remote')
    if not DIAG then check(#f.events==1 and f.events[1].kind=='startup','Release has no per-frame or request log writes')end
end
do
    local f,e,m,tick=setup();f.left=true;f.hook=function()f.active=true;f.ability=521;f.clock=.01 end;tick();f.hook=nil
    f.right=true;tick();check(m.requests.pending and f.remotes==0 and f.starts==0,'early right waits for this throw')
    f.hook=function()f.clock=.2;f.release=true;f.targets={{identity='new'}}end;tick();f.hook=nil
    check(f.remotes==1 and f.starts==0 and f.left and not m.disabled,'released521 with left held uses remote')
end
do
    local f,e,m,tick=setup();f.left=true;f.right=true;f.hook=function()f.active=true;f.ability=521;f.clock=.01 end;tick();f.hook=nil
    check(m.requests.pending and f.starts==0,'same-frame competition stays pending')
    f.left=false;f.right=false;f.clock=.2;f.release=true;tick();check(f.remotes==0,'phase without new target insufficient')
    f.active=false;f.avatar=true;f.targets={{identity='new'}};tick()
    check(f.remotes==1 and f.starts==0,'latched released throw can dispatch during reload')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.transition=true;f.right=true;tick()
    check(f.starts==0 and f.remotes==0 and not f.gate,'before-phase transition blocks and restores Aim')
    f.transition=false;tick();check(f.starts==0 and not f.gate,'held RMB cannot reacquire after transition')
    f.right=false;tick();f.right=true;tick();check(f.starts==1,'fresh baseline and new edge restore operation')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.right=true;f.hook=function()f.transition=true end;tick()
    check(f.starts==0 and f.remotes==0 and not f.gate,'after original transition cancels before commit')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.right=true;f.final_transition=true;tick()
    check(f.starts==0 and f.remotes==0 and not f.gate and not m.disabled,'fresh final transition veto cancels safely')
end
do
    local f,e,m,tick=setup{mode=1};check(f.writes==1 and f.mode==0 and f.gate,'idle mode1 auto-normalized without manual menu')
    tick();check(f.writes==1,'mode0 never rewritten each frame')
    f.scope=false;f.mode=1;tick();check(f.writes==1 and not f.gate,'unequipped instance never normalized')
end
do
    local f,e,m,tick=setup();f.mode=1;f.left=true;tick();check(f.writes==0 and not f.gate,'held left defers new mode normalization')
    f.left=false;tick();check(f.writes==1 and not m.disabled,'released idle baseline permits normalization')
end
do
    local f,e,m,tick=setup{no_action=true};f.targets={{identity='old'}};f.right=true;tick()
    check(f.remotes==1 and f.starts==0 and not m.disabled,'optional action signature mismatch retains remote')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.no_start_observed=true;f.right=true;tick();f.t=f.t+.6;tick()
    check(m.disabled and f.starts==1 and f.remotes==0 and not f.gate,'uncertain native520 completion stops without fallback')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.start_error=true;f.right=true;tick()
    check(m.disabled and f.starts==1 and f.remotes==0 and not f.gate,'uncertain start never also remote')
end
do
    local f,e,m,tick=setup();f.avatar=true;f.targets={{identity='old'}};f.call_error=true;f.right=true;tick()
    check(m.disabled and f.remotes==1 and f.starts==0 and not f.gate,'uncertain remote never also520')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.avatar=true;f.right=true;tick()
    check(f.captures==1 and f.remotes==1,'no post-action target rescan')
    f.target_error=true;tick();check(not m.disabled and f.remotes==1,'later observation failure cannot replay consumed request')
end
do
    local f,e,m,tick=setup();f.original_error=true
    local ok,why=pcall(tick);check(not ok and tostring(why):find('original%-sentinel')and m.disabled and not f.gate,'original exception propagates and cleans lease')
end
do
    local f,e,m,tick=setup{old=true};check(m.disabled and not f.gate and f.starts==0 and f.remotes==0,'legacy addon conflict fails before effects')
end
do
    local f,e,m,tick=setup();f.mode=1;f.write_error=true;tick()
    check(m.disabled and f.writes==0 and not f.gate,'unconfirmed mode write releases Aim and disables actions')
end
do
    local f,e,m,tick=setup();f.left=true;f.hook=function()f.active=true;f.ability=521;f.clock=.01 end;tick();f.hook=nil
    f.right=true;tick();check(m.requests.pending,'pending right precedes transition')
    f.transition=true;tick();check(not m.requests.pending and not f.gate,'transition discards unsubmitted pending')
    f.active=false;f.release=true;f.left=false;f.transition=false;f.targets={{identity='new'}};tick()
    check(f.starts==0 and f.remotes==0,'discarded pending is never replayed after equip settles')
end
do
    local f,e,m,tick=setup();f.targets={{identity='old'}};f.right=true;f.hook=function()f.ui=true end;tick()
    check(f.starts==0 and f.remotes==0 and not f.gate,'UI during original callback cancels dispatch')
end
return checks
