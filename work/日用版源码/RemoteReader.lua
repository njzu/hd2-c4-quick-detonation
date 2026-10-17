-- Minimal owner-batch target evidence, derived from upstream ContactReader.
-- Never calls the single-projectile explode path or collision/physics APIs.
local bit=require('bit')
local M={}
local CHARGE='\103\221\18\131\125\33\117\155'
function M.capture(api,game,base,scope)
    local guards,reads,bytes={},0,0
    local function read(at,n)
        reads=reads+1;bytes=bytes+n
        assert(reads<=768 and bytes<=131072,'REMOTE_READ_BUDGET')
        assert(type(at)=='number' and at>=65536 and at+n<0x800000000000 and n>0 and n<=4096,'remote_read_bounds')
        local b=assert(api.read(at,n),'remote_read_unavailable');assert(#b==n,'remote_short_read')
        guards[#guards+1]={at=at,bytes=b};return b
    end
    local function ptr(at)return assert(api.pointer(read(at,8)),'remote_pointer')end
    local function global(rva)return ptr(game+assert(rva))end
    local u32=base.u32
    local function lookup(at,key,limit)
        local h=read(at,20);local n,empty,mult=u32(h,8),u32(h,12),u32(h,16)
        assert(n<=limit and (n==0 or bit.band(n,n-1)==0),'remote_map_layout')
        if n==0 or key==empty or key==0xffffffff then return nil end
        local data=assert(api.pointer(h),'remote_map_pointer')
        for probe=0,math.min(n,128)-1 do
            local b=read(data+((base.product_low(key,mult)+probe)%n)*8,8);local k=u32(b,0)
            if k==key then local v=u32(b,4);return v~=0xffffffff and v or nil end
            if k==empty then return nil end
        end
        error('remote_probe_budget')
    end
    local owner=global(C.global_contact_owner)
    assert(owner==scope.owner and global(C.global_contact_world)==scope.root,'remote_world_changed')
    local wi=assert(lookup(owner+D.entity_id_map,scope.weapon_id,1048576),'remote_weapon_missing')
    assert(wi<262144 and read(owner+D.entity_array+wi*24,24)==scope.weapon,'remote_weapon_reused')
    local remote=global(C.global_contact_remote)
    local count=u32(read(remote+0x10,4),0);assert(count<=128,'remote_registry_capacity')
    local result={manager=remote,identity=scope.identity,all={},eligible={},set={},raw_reads=0}
    if count>0 then
        local registry,links=ptr(remote+0x38),ptr(remote+0x48)
        for i=0,count-1 do
            local entity=read(ptr(registry+i*8),24)
            if entity:sub(1,8)==CHARGE and bit.band(entity:byte(21),1)~=0 then
                local reference=u32(read(links+i*8,8),0)
                local oi=reference~=0x7fff and lookup(owner+D.entity_unit_map,reference,1048576)
                if oi then
                    assert(oi<262144,'remote_owner_index')
                    if read(owner+D.entity_array+oi*24,24)==scope.weapon then
                        local id,unit=u32(entity,8),u32(entity,12)
                        assert(lookup(remote+0x20,id,65536)==i,'remote_registry_identity')
                        local ei=assert(lookup(owner+D.entity_id_map,id,1048576),'remote_entity_missing')
                        assert(ei<262144 and read(owner+D.entity_array+ei*24,24)==entity,'remote_entity_reused')
                        assert(unit~=0 and lookup(owner+D.unit_entity_id_map,unit,1048576)==id,'remote_unit_identity')
                        local explosive=global(C.global_contact_explosive)
                        local xi=assert(lookup(explosive+0x38,id,65536),'remote_explosive_missing')
                        assert(xi<4096,'remote_explosive_index')
                        assert(read(ptr(ptr(explosive+0x50)+xi*8),24)==entity,'remote_explosive_reused')
                        local network=read(ptr(explosive+0x68)+xi*56,2)
                        assert(network:byte(2)<=1,'remote_requested_flag')
                        local key=entity
                        local item={id=id,identity=key,requested=network:byte(2)==1,authority='ENTITY_LOCAL_OWNERSHIP_BIT'}
                        result.all[#result.all+1]=item;result.set[key]=true
                        if not item.requested then result.eligible[#result.eligible+1]=item end
                    end
                end
            end
        end
    end
    result.same=GuardSpans.checker(api,guards,false)
    assert(result.same() and scope.same(),'remote_snapshot_changed')
    result.raw_reads=reads
    return result
end
return M
