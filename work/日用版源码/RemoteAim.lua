-- Aim ownership belongs to scope, not weapon/avatar busy state.
local M={}
function M.new(api,game,base,native,verify,validate,emit,invalidate,clock)
    local self={lease=nil}
    clock=clock or os.clock
    local hints={}
    self.stats={held_reads=0,reused=0,rebuilt=0,fresh_reads=0,invalidations=0}
    local function clear()hints={};if DIAGNOSTICS then self.stats.invalidations=self.stats.invalidations+1 end end
    self.invalidate=clear
    local spec={action=D.input_aim_action,code=D.input_aim_code,index=8,fire=true}
    local function read(held)
        if not held then if DIAGNOSTICS then self.stats.fresh_reads=self.stats.fresh_reads+1 end;return AimInputState.read(api,game,base,nil,nil,spec)end
        local old=hints.cache
        local p=AimInputState.read(api,game,base,true,nil,spec,nil,hints)
        if DIAGNOSTICS then self.stats.held_reads=self.stats.held_reads+1 end
        if DIAGNOSTICS then local key=old and hints.cache==old and 'reused' or 'rebuilt';self.stats[key]=self.stats[key]+1 end
        return p
    end
    function self.stop()
        local old=self.lease;if not old then clear();return true end
        local p=read(false)
        if p.owner==old.owner and p.mask and (p.mask.bytes==old.expected or old.pending and
            p.mask.mode==1 and p.mask.bytes:sub(17,24)==string.rep('\0',8)) then
            verify('fn_input_unblock');assert(p.same(),'aim_release_changed')
            clear();invalidate();native.unblock(p.owner,spec.action)
            local q=read(false);assert(q.owner==p.owner and q.mask and q.mask.mode==0,'aim_release_unconfirmed')
        end
        self.lease=nil;clear();if emit then emit('aim_lease',{owned=false})end;return true
    end
    function self.sync(cap,enabled,released)
        if not enabled or not cap then self.stop();return false end
        local p=read(true)
        if self.lease and (self.lease.owner~=p.owner or self.lease.identity~=cap.identity or
            not p.mask or p.mask.bytes~=self.lease.expected) then self.stop();p=read(true) end
        if self.lease then return true end
        if not released or p.held or p.mask and p.mask.mode~=0 then return false end
        assert(p.mask or p.count<D.input_inhibit_capacity,'aim_capacity')
        validate(cap)
        verify('fn_input_inhibit');assert(cap.same() and p.same(),'aim_acquire_changed')
        self.lease={owner=p.owner,identity=cap.identity,pending=true}
        clear();invalidate();native.inhibit(p.owner,spec.action)
        local q=read(false)
        assert(q.owner==p.owner and q.mask and q.mask.mode==1 and q.mask.bytes:sub(17,24)==string.rep('\0',8),'aim_acquire_unconfirmed')
        self.lease.expected=q.mask.bytes;self.lease.pending=false;if emit then emit('aim_lease',{owned=true})end
        return true
    end
    function self.valid(cap)
        local old=self.lease;if not old or old.identity~=cap.identity then return false end
        local p=read(false)
        return p.owner==old.owner and p.mask and p.mask.bytes==old.expected and p.same()
    end
    return self
end
return M
