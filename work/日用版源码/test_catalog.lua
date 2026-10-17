local f=assert(io.open('private/tests/mock-native.bin','rb'));local image=f:read('*a');f:close()
local base=0x10000000
local api={read=function(at,n)assert(n<=4096);local p=at-base;if p<0 or p+n>#image then return end;return image:sub(p+1,p+n)end}
local scan=NativeResolver.new_scan(api,base)
local native=NativeResolver.resolve(api,base,NativeCatalog,scan)
local remote=NativeResolver.resolve(api,base,RemoteCatalog,scan)
local action=NativeResolver.resolve(api,base,ActionCatalog,scan)
scan.release()
assert(native.symbols.fn_input_inhibit and remote.symbols.contact_remote_owner)
native.verify();remote.verify()
action.verify()
assert(action.symbols.fn_detonate_lifecycle==remote.symbols.contact_remote_lifecycle,'native520 lifecycle must equal verified remote lifecycle')
local at=remote.symbols.contact_remote_owner
local original=image
image=image:sub(1,at)..'\0'..image:sub(at+2)
assert(not pcall(remote.verify),'changed remote owner code must invalidate dispatch')
image=original
local at2=native.symbols.fn_input_inhibit
image=image:sub(1,at2)..'\0'..image:sub(at2+2)
assert(not pcall(native.verifier_for('fn_input_inhibit')),'changed input routine must invalidate acquisition')
image=original;remote.verify();native.verify()
local selector
for _,node in ipairs(NativeCatalog.nodes)do if node.name=='fn_weapon_functions'then selector=node end end
local selector_at=native.symbols.fn_weapon_functions
image=image:sub(1,selector_at)..string.char((image:byte(selector_at+1)+1)%256)..image:sub(selector_at+2)
assert(not pcall(native.verifier_for('fn_weapon_functions')),'changed instance selector getter invalidates write admission')
image=original
local dispatch
for _,node in ipairs(ActionCatalog.nodes)do if node.abilities then dispatch=node end end
local function u32(offset)local a,b,c,d=image:byte(offset+1,offset+4);return a+b*256+c*65536+d*16777216 end
local table_at=u32(action.symbols[dispatch.name]+dispatch.abilities.operand)
local entry=table_at+(520-1)*4
local value=u32(table_at+(521-1)*4)
local bytes=string.char(value%256,math.floor(value/256)%256,math.floor(value/65536)%256,math.floor(value/16777216)%256)
image=image:sub(1,entry)..bytes..image:sub(entry+5)
assert(not pcall(action.verify),'520 dispatch mapped to deploy is rejected before any native start')
image=original;action.verify()
return 9
