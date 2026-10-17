-- Event-only strict admission copied from the reference native gates; no ammo walk.
local bit=require('bit');local M={}
function M.capture(api,game,base,wanted)
    if wanted.active or wanted.avatar_active or wanted.veto or not wanted.standing or wanted.transition then return nil,'BUSY_OR_UNSUPPORTED_POSE'end
    local row,why,result=base.snapshot(api,game,function(e,row)
        local read,ptr,u32=e.read,e.ptr,e.u32
        assert(e.entity..e.weapon..':'..tostring(e.owner)..':'..tostring(e.global(C.global_contact_world))==wanted.native_identity,'idle_identity_changed')
        local function component(manager,map,registry)
            local i=assert(e.lookup(manager+map,e.weapon_id,65536),'idle_component_missing');assert(i<4096,'idle_component_index')
            assert(read(ptr(ptr(manager+registry,true)+i*8,true),24,true)==e.weapon,'idle_component_owner');return i
        end
        local wm=e.global(R.global_weapon);local wi=component(wm,0x28,0x40)
        local flags=u32(read(ptr(wm+0x50,true)+wi*40,4,true),0)
        assert(bit.band(flags,0x19)==8,'idle_weapon_kind')
        local fm=e.global(R.global_fire_latch);local fi=component(fm,0x20,0x38)
        assert(read(ptr(fm+0x48,true)+fi*8,1,true):byte()==0,'idle_fire_held')
        local blocker=e.global(R.global_blocker);local bi=e.lookup(blocker+D.blocker_map,e.weapon_id,65536)
        if bi then
            assert(bi<4096,'idle_block_index');assert(u32(read(ptr(blocker+D.blocker_states,true)+bi*0x1b8+0x19c,4,true),0)<2,'idle_native_blocked')
        end
        local exclusions=e.global(R.global_exclusions);local ei=e.lookup(exclusions+0x20,e.weapon_id,65536)
        assert(not ei or ei<4096,'idle_exclusion_index')
        local f=ei and u32(read(ptr(exclusions+0x50,true)+ei*4,4,true),0)or 0
        assert(not((bit.band(f,1)~=0 and bit.band(f,2)==0)or(bit.band(f,8)~=0 and bit.band(f,16)==0)or
            (bit.band(f,32)~=0 and bit.band(f,64)==0)or bit.band(f,4)~=0),'idle_native_excluded')
        return{manager=e.global(R.global_ability),same=e.checked}
    end)
    if not result then return nil,why or row and row.action_context_error or 'IDLE_UNKNOWN'end
    assert(result.same() and wanted.same(),'idle_changed');return result
end
return M
