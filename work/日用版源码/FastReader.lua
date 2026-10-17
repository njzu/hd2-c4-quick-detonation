-- Narrow local scope and weapon ability. No ammo/reload capability or native action call.
local M={}
local bit=require('bit')
local function identity(e,root)
    return e.entity..e.weapon..':'..tostring(e.owner)..':'..tostring(root)
end
function M.snapshot(api,game,base)
    return base.snapshot(api,game,function(e,row)
        local read,ptr,u32=e.read,e.ptr,e.u32
        local root=e.global(C.global_contact_world)
        local cap={identity=identity(e,root),owner=e.owner,root=root,weapon=e.weapon,
            weapon_id=e.weapon_id,same=e.checked,active=false,released=false}
        cap.flags_at=e.avatar+0x53e880+e.avatar_index*0x1238
        local av=e.avatar_flags
        if not AvatarFlags.has(av,D.alive) then cap.cancel='NOT_ALIVE'
        elseif AvatarFlags.has(av,D.seated) then cap.cancel='VEHICLE_OUT_OF_SCOPE'
        elseif AvatarFlags.has(av,D.tactical_map) then cap.cancel='MAP'
        elseif AvatarFlags.has(av,D.weapon_menu) then cap.cancel='WEAPON_MENU' end
        cap.transition=AvatarFlags.has(av,111)
        cap.operable=not cap.transition
        for _,flag in ipairs(D.blocked) do
            if flag~=D.airborne and flag~=D.prone and flag~=D.diving and flag~=D.seated
                and AvatarFlags.has(av,flag) then
                -- Unknown flags are NOT called reload or whitelisted by an ability number.
                cap.veto='UNCLASSIFIED_AVATAR_FLAG_'..flag;row.avatar_blocking_flag=flag;break
            end
        end
        local am=e.global(R.global_ability)
        local function ability(id,entity)
            local i=assert(e.lookup(am+0x18,id,65536),'ability_component_missing')
            assert(i<4096,'ability_index')
            assert(read(ptr(ptr(am+0x30,true)+i*8,true),24,true)==entity,'ability_owner_changed')
            local b=read(ptr(am+0x38,true)+i*0xe0,32,true)
            assert(b:byte(17)<=1,'ability_active_flag')
            return b
        end
        local b=ability(e.weapon_id,e.weapon)
        cap.active=b:byte(17)==1;cap.ability=u32(b,0)
        if cap.active and cap.ability==521 then
            cap.clock=base.f32(b,8);assert(cap.clock>=0 and cap.clock<3600,'throw_clock')
            cap.released=b:byte(18)==0 and cap.clock*D.ability_phase_hz>=D.c4_release_phase
        end
        local avatar=ability(e.id,e.entity)
        row.avatar_ability_active=avatar:byte(17)==1;row.avatar_ability_id=u32(avatar,0)
        cap.avatar_active=row.avatar_ability_active
        cap.standing=not AvatarFlags.has(av,D.airborne) and not AvatarFlags.has(av,D.prone) and not AvatarFlags.has(av,D.diving)
        local wd=e.global(R.global_weapon_data)
        local di=assert(e.lookup(wd+0x30,e.weapon_id,65536),'mode_component_missing')
        local count=u32(read(wd+0x1c,4,true),0)
        assert(count<=4096 and di<count,'mode_component_index')
        assert(read(ptr(ptr(wd+0x48,true)+di*8,true),24,true)==e.weapon,'mode_component_owner')
        local config=ptr(wd+0x58,true)+di*D.weapon_data_stride
        local types=read(config+D.weapon_types,16,true)
        assert(u32(types,0)==10 and u32(types,4)==0 and u32(types,8)==0 and u32(types,12)==0,'mode_type10_instance_required')
        local store=ptr(wd+0x60,true)
        local at=store+di*12+4
        assert(at%4==0 and not(at>=config and at<config+D.weapon_data_stride),'mode_storage_alias')
        local packed=read(at,4,true);local word=u32(packed,0)
        local value=bit.band(bit.rshift(word,8),3);assert(value<=1,'unsupported_c4_mode')
        cap.mode={value=value,at=at,bytes=packed,word=word,store=store,count=count,index=di}
        -- Observe avatar activity, but do not equate it with scope loss or a submit veto.
        row.native_action_active=cap.active;row.active_ability_id=cap.ability
        row.deploy_released=cap.released;row.native_ability_time=cap.clock
        cap.scope=not cap.cancel and row.selected_slot==3
        return cap
    end,'routing')
end
local EXPECTED='090200000000000000000000000000003482df840000000014f02aa3c6abad38010100000000000008020000000000000000000000000000926c9d6c00000000f8934147834337550001000000000000'
local bytes=(EXPECTED:gsub('..',function(s)return string.char(tonumber(s,16))end))
local function gameplay(b)return b:sub(1,16)..b:sub(21,56)..b:sub(61,80)end
function M.validate(api,game,base,wanted,allow_one)
    -- Once per acquisition/weapon lifetime, not every frame. No ActionReader/reload/ammo walk.
    local row,why,cap=base.snapshot(api,game,function(e,row)
        assert(e.ability_template and gameplay(e.ability_template)==gameplay(bytes),'c4_descriptor_changed')
        assert(row.weapon_function_types and row.weapon_function_types['0']==10,'c4_selector_type')
        local value=row.weapon_function_values['0']
        assert(value==0 or allow_one and value==1,'DEPLOY_MODE_REQUIRED')
        local root=e.global(C.global_contact_world)
        assert(identity(e,root)==(wanted.native_identity or wanted.identity),'c4_acquire_identity_changed')
        return {same=e.checked}
    end)
    assert(cap,why or row and row.action_context_error or 'c4_descriptor_unavailable')
    assert(cap.same() and wanted.same(),'c4_acquire_changed')
    return true
end
function M.live_operable(api,cap)
    local flags=assert(api.read(cap.flags_at,24),'final_flags_unreadable')
    if AvatarFlags.has(flags,111) then return false,'EQUIPMENT_TRANSITION' end
    if not AvatarFlags.has(flags,D.alive) or AvatarFlags.has(flags,D.seated) or
        AvatarFlags.has(flags,D.tactical_map) or AvatarFlags.has(flags,D.weapon_menu) then return false,'FINAL_SCOPE_VETO'end
    return true
end
return M
