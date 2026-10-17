-- No FFI. Requests are consumed BEFORE native effects and never retried.
local M={}
function M.new(emit)
    local s={identity=nil,armed=false,epoch=0,serial=0,throw=nil,pending=nil,fault=nil,
        previous_throw=false,previous_clock=nil,state='DISARMED'}
    local function state(value,why)
        if value~=s.state or why~=s.reason then
            s.state,s.reason=value,why
            if emit then emit('state',{state=value,reason=why,throw_epoch=s.epoch,request_id=s.pending and s.pending.id})end
        end
    end
    function s.drop(why)
        if s.pending and emit then emit('request_cancelled',{request_id=s.pending.id,throw_epoch=s.pending.epoch,reason=why}) end
        s.pending=nil
    end
    function s.cancel(why)
        s.drop(why);s.identity=nil;s.armed=false;s.throw=nil;s.previous_throw=false;s.previous_clock=nil
        s.pre=nil;state(s.fault and 'FAULT' or 'DISARMED',why)
    end
    function s.fail(why)s.fault=tostring(why);s.cancel(s.fault);if emit then emit('fault',{reason=s.fault,outcome='NO_RETRY_NO_PATH_SWITCH'})end end
    function s.observe(ctx,now,frame,phase)
        s.new_epoch=false;s.just_released=false
        if s.fault then return false end
        if not ctx or not ctx.scope then s.cancel(ctx and ctx.cancel or 'SCOPE_UNAVAILABLE');return false end
        if ctx.operable==false then s.cancel('EQUIPMENT_TRANSITION');return false end
        if s.identity~=ctx.identity then s.cancel('IDENTITY_CHANGED');s.identity=ctx.identity end
        local throwing=ctx.active and ctx.ability==521
        if throwing and (not s.previous_throw or s.previous_clock and ctx.clock<s.previous_clock-.0001) then
            if s.pending and not s.pending.wait_new then s.drop('THROW_EPOCH_CHANGED') end
            s.epoch=s.epoch+1;s.new_epoch=true
            s.throw={id=s.epoch,released=false,finished=false}
            if s.pre and s.pre.identity==ctx.identity and frame<=s.pre.frame+1 then s.throw.baseline=s.pre.set end
            s.pre=nil
            if emit then emit('throw_begin',{throw_epoch=s.epoch,clock=ctx.clock,identity=ctx.identity})end
        end
        if throwing and s.throw and ctx.released and not s.throw.released then
            s.throw.released=true;s.just_released=true
            if emit then emit('throw_release_observed',{throw_epoch=s.epoch,evidence='NATIVE_PHASE_REQUIRES_NEW_TARGET_ASSOCIATION'})end
        end
        if not throwing and s.previous_throw and s.throw then
            s.throw.finished=true
            if not s.throw.released then s.drop('THROW_ENDED_WITHOUT_RELEASE') end
            if emit then emit('throw_end',{throw_epoch=s.epoch,release_observed=s.throw.released})end
        end
        s.previous_throw=throwing;s.previous_clock=throwing and ctx.clock or nil
        if s.pending and s.pending.wait_new and s.new_epoch then
            s.pending.wait_new=false;s.pending.epoch=s.epoch
        end
        if s.pending and s.pending.wait_new and phase=='after' and frame>s.pending.frame then s.drop('COMPETING_THROW_NOT_OBSERVED') end
        if ctx.veto then
            -- Unknown posture may include ragdoll. Cancel a request, not scope/Aim ownership.
            s.drop(ctx.veto);s.armed=false;state('WAIT_RELEASE',ctx.veto);return false
        end
        if s.pending and now-s.pending.at>1.5 then s.drop('TTL_EXPIRED') end
        if s.pending and s.pending.epoch and s.pending.epoch~=s.epoch then s.drop('STALE_THROW_EPOCH') end
        return true
    end
    function s.baseline(set,frame)
        if s.throw and s.previous_throw and not s.throw.released and not s.throw.baseline then s.throw.baseline=set end
        s.pre={set=set,frame=frame,identity=s.identity}
    end
    function s.input(ctx,input,now,frame)
        if s.fault or not ctx or not ctx.scope or ctx.veto or ctx.operable==false then return end
        if not ctx.aim_owned then s.drop('AIM_NOT_OWNED');s.armed=false;state('WAIT_RELEASE','AIM_NOT_OWNED');return end
        if not s.armed then
            if not input.left and not input.right then s.armed=true end
            state('WAIT_RELEASE');return
        end
        if input.right_edge and not s.pending then
            s.serial=s.serial+1
            local competing=input.left_edge and not s.new_epoch
            s.pending={id=s.serial,at=now,identity=ctx.identity,frame=frame,reads=0,
                epoch=s.previous_throw and s.epoch or nil,wait_new=competing}
            if emit then emit('input_accepted',{request_id=s.serial,throw_epoch=s.pending.epoch,identity=ctx.identity,wait_new=competing})end
        end
        if not s.pending then state('READY') end
    end
    function s.can_read()
        local p=s.pending;if not p or p.wait_new then return false end
        if p.epoch then
            local t=s.throw
            if not t or t.id~=p.epoch then s.drop('STALE_THROW_EPOCH');return false end
            if not t.released then state('PENDING_RELEASE');return false end
            if not t.baseline then s.drop('RELEASE_WITHOUT_BASELINE');state('READY','RELEASE_WITHOUT_BASELINE');return false end
        end
        return true
    end
    function s.targets(targets,reads)
        local p=s.pending;if not p then return false end
        p.reads=p.reads+reads
        if p.reads>4096 then s.drop('REQUEST_READ_BUDGET');return false end
        local eligible=targets.eligible
        if p.epoch then
            local found=false
            for _,item in ipairs(eligible) do if not s.throw.baseline[item.identity] then found=true;break end end
            if not found then state('PENDING_TARGET','NEW_OWNED_ENTITY_NOT_VISIBLE');return false end
        elseif #eligible==0 then s.drop('NO_TARGET');state('READY','NO_TARGET');return false end
        if #eligible==0 then return false end
        return true
    end
    function s.commit_ready(now)
        if not s.pending or s.fault then return false end
        if now-s.pending.at>1.5 then s.drop('TTL_EXPIRED_BEFORE_COMMIT');return false end
        return s.pending.identity==s.identity and s.can_read()
    end
    function s.submitted(path)
        local p=assert(s.pending,'missing_request')
        p.path=path or 'REMOTE'
        s.pending=nil;state('SUBMITTED')
        if emit then emit('remote_submit',{request_id=p.id,throw_epoch=p.epoch,identity=p.identity,path=p.path,result='MARKED_BEFORE_NATIVE_CALL'})end
        return p
    end
    return s
end
return M
