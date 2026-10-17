local ffi=require('ffi');local bit=require('bit');local n=0
local function check(v,s)assert(v,s);n=n+1 end
local backing=ffi.new('uint32_t[12]');backing[4]=0xa5a5015a
local address=tonumber(ffi.cast('uintptr_t',backing))
local api=WindowsRead();local exchange=InstanceWrite.new(api)
local cap={mode={store=address,index=1,count=4,at=address+16},same=function()return true end}
local old=api.read(address+16,4);local value=ffi.new('uint32_t[1]',bit.band(backing[4],bit.bnot(0x300)))
local bytes=ffi.string(value,4)
check(exchange(cap,old,bytes) and backing[4]==0xa5a5005a,'real private RW buffer selector-only compare/write/readback')
check(not pcall(exchange,cap,old,bytes) and backing[4]==0xa5a5005a,'stale expected bytes never overwrite')
cap.same=function()return false end
check(not pcall(exchange,cap,bytes,bytes),'changed context rejects before write')
cap.same=function()return true end
local image=assert(api.module('kernel32.dll'));local original=api.read(image+4,4)
local word=ContextReader.u32(original,0);value[0]=bit.band(word,bit.bnot(0x300))
local other={mode={store=image,index=0,count=1,at=image+4},same=function()return true end}
check(not pcall(exchange,other,original,ffi.string(value,4)) and api.read(image+4,4)==original,'image page rejected without protection changes')
local calls=0;local invalid=0
local mode=ModeControl.new(function(_,a,b)calls=calls+1;assert(a~=b)end,
    function(_,allow)assert(allow)end,function()end,function()invalid=invalid+1 end)
local c={scope=true,operable=true,mode={value=1,word=0x100,bytes='\0\1\0\0'},same=function()return true end}
check(not mode.ready(c,{left=true}), 'held left delays normalization')
check(not mode.ready(c,{right=true}), 'held right delays normalization')
c.active=true;check(not mode.ready(c,{}),'active ability delays normalization');c.active=false
c.operable=false;check(not mode.ready(c,{}),'transition delays normalization');c.operable=true
local ready,why=mode.ready(c,{})
check(not ready and why=='MODE_NORMALIZED_REQUIRE_BASELINE' and calls==1 and invalid==1,'one idle write invalidates and requires baseline')
c.mode.value=0;check(mode.ready(c,{left=true}) and calls==1,'DEPLOY requires no recurring write')
return n
