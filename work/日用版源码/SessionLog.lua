-- Release: startup, one-time failures and shutdown only. No periodic flush task.
local M={}
function M.json(v)
    local t=type(v)
    if t=='nil'then return'null'end
    if t=='boolean'then return tostring(v)end
    if t=='number'then return v==v and v~=math.huge and v~=-math.huge and string.format('%.12g',v)or'null'end
    if t=='string'then return'"'..v:gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',c:byte())end)..'"'end
    local out={};if t~='table'then return'null'end
    for k,x in pairs(v)do if type(k)=='string'and type(x)~='function'and type(x)~='cdata'then out[#out+1]=M.json(k)..':'..M.json(x)end end
    return'{'..table.concat(out,',')..'}'
end
function M.new(loader,diagnostic)
    local log=RollingLog.new(loader.open_log,M.json,diagnostic and 'C4QuickDiagnostic'or'C4QuickRelease',
        function()return{schema=2,version='1.0.0-rc1',diagnostic=diagnostic,session=os.date('!%Y%m%dT%H%M%SZ')}end,
        {max_bytes=524288,slots=4})
    local seen={};local self={}
    function self.once(kind,fields)
        if seen[kind]then return end;seen[kind]=true
        fields=fields or {};fields.kind=kind;assert(log:write(M.json(fields)..'\n'));assert(log:flush())
    end
    function self.event(kind,fields)
        fields=fields or {};fields.kind=kind;assert(log:write(M.json(fields)..'\n'))
    end
    function self.flush()assert(log:flush())end
    function self.close()log:flush();log:close()end
    return self
end
return M
