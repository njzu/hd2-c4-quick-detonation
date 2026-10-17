-- Normalize the current entity's instance word. Never restores into an unequipped entity.
local bit=require('bit')
local M={}
local function pack(v)
    return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
end
function M.new(exchange,validate,verify,invalidate,record)
    local self={writes=0}
    function self.ready(cap,input)
        if not cap.scope or cap.operable==false then return false,'MODE_SCOPE_NOT_OPERABLE'end
        if cap.mode.value==0 then return true end
        if cap.active or cap.avatar_active or cap.veto or input.left or input.right then return false,'WAIT_IDLE_RELEASE_FOR_MODE' end
        validate(cap,true);verify();assert(cap.same(),'mode_normalize_changed')
        local value=pack(bit.band(cap.mode.word,bit.bnot(0x300)))
        exchange(cap,cap.mode.bytes,value);invalidate();self.writes=self.writes+1
        if record then record('mode_normalized',{weapon_id=cap.weapon_id,writes=self.writes})end
        return false,'MODE_NORMALIZED_REQUIRE_BASELINE'
    end
    return self
end
return M
