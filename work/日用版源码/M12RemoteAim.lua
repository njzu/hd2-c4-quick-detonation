-- Aim ownership belongs to scope, not weapon/avatar busy state.
local M={}
function M.new(api,game,base,native,verify,validate,emit,invalidate,clock)
    local self={lease=nil}
    clock=clock or os.clock
    local spec={action=D.input_aim_action,code=D.input_aim_code,index=8,fire=true}
    local function read(held)return AimInputState.read(api,game,base,held and true or nil,nil,spec)end
    function self.stop()
        local old=self.lease;if not old then return true end
        local p=read(false)
        if p.owner==old.owner and p.mask and (p.mask.bytes==old.expected or old.pending and
            p.mask.mode==1 and p.mask.bytes:sub(17,24)==string.rep('\0',8)) then
            verify('fn_input_unblock');assert(p.same(),'aim_release_changed')
            invalidate();native.unblock(p.owner,spec.action)
            local q=read(false);assert(q.owner==p.owner and q.mask and q.mask.mode==0,'aim_release_unconfirmed')
        end
        self.lease=nil;emit('aim_lease',{owned=false});return true
    end
    function self.sync(cap,enabled,released)
        if not enabled or not cap then self.stop();return false end
        if not self.lease and self.mode_wait_identity==cap.identity and clock()<self.mode_retry_at then return false end
        local p=read(true)
        if self.lease and (self.lease.owner~=p.owner or self.lease.identity~=cap.identity or
            not p.mask or p.mask.bytes~=self.lease.expected) then self.stop();p=read(true) end
        if self.lease then return true end
        if not released or p.held or p.mask and p.mask.mode~=0 then return false end
        assert(p.mask or p.count<D.input_inhibit_capacity,'aim_capacity')
        local qualified,why=pcall(validate,cap)
        if not qualified then
            if tostring(why):find('M12_REQUIRES_DEPLOY_MODE',1,true) then
                if self.mode_wait_identity~=cap.identity then emit('mode_wait',{reason='M12_REQUIRES_DEPLOY_MODE',identity=cap.identity})end
                self.mode_wait_identity=cap.identity;self.mode_retry_at=clock()+.25;return false
            end
            error(why,0)
        end
        self.mode_wait_identity=nil
        verify('fn_input_inhibit');assert(cap.same() and p.same(),'aim_acquire_changed')
        self.lease={owner=p.owner,identity=cap.identity,pending=true}
        invalidate();native.inhibit(p.owner,spec.action)
        local q=read(false)
        assert(q.owner==p.owner and q.mask and q.mask.mode==1 and q.mask.bytes:sub(17,24)==string.rep('\0',8),'aim_acquire_unconfirmed')
        self.lease.expected=q.mask.bytes;self.lease.pending=false;emit('aim_lease',{owned=true})
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
