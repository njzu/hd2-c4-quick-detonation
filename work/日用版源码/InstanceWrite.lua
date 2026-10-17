-- Only a verified instance selector word on committed, private PAGE_READWRITE.
-- Microsoft MEMORY_BASIC_INFORMATION x64 layout, private FFI name; no protection change.
local M={}
function M.new(api)
    local ffi=require('ffi');local bit=require('bit');local k=WinApi.load()
    ffi.cdef[[typedef struct {void *base;void *allocation;uint32_t allocation_protect;uint16_t partition;
        size_t region_size;uint32_t state;uint32_t protect;uint32_t kind;} c4daily_mbi;
        size_t c4daily_VirtualQuery(const void *,c4daily_mbi *,size_t) __asm__("VirtualQuery");]]
    local mbi=ffi.new('c4daily_mbi[1]');local size=ffi.sizeof('c4daily_mbi')
    assert(size==48,'unexpected_windows_x64_mbi')
    local count=ffi.new('size_t[1]');local process=k.c4qa_GetCurrentProcess()
    return function(cap,expected,value)
        local m=assert(cap.mode,'mode_capability_missing');local at=m.at
        assert(#expected==4 and #value==4 and at%4==0 and at==m.store+m.index*12+4 and m.index<m.count,'instance_write_bounds')
        local old,new=ContextReader.u32(expected,0),ContextReader.u32(value,0)
        assert(bit.band(old,bit.bnot(0x300))==bit.band(new,bit.bnot(0x300)) and bit.band(new,0x300)==0,'selector_only_write')
        assert(k.c4daily_VirtualQuery(ffi.cast('const void *',at),mbi,size)==size,'mode_page_query_failed')
        local b=mbi[0];local first=tonumber(ffi.cast('uintptr_t',b.base))
        assert(b.state==0x1000 and b.kind==0x20000 and b.protect==4 and at>=first and at+4<=first+tonumber(b.region_size),'mode_page_not_private_rw')
        assert(cap.same() and api.read(at,4)==expected,'mode_write_context_changed')
        assert(k.c4qa_WriteProcessMemory(process,ffi.cast('void *',at),value,4,count)~=0 and tonumber(count[0])==4,'mode_write_failed')
        assert(api.read(at,4)==value,'mode_write_readback_failed')
        return true
    end
end
return M
