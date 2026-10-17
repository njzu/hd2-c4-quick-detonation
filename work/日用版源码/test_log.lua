local writes,flushes,closes,opens=0,0,0,0
local lines={}
local loader={open_log=function(name)
    opens=opens+1;assert(name:find('C4QuickRelease_part',1,true))
    return{write=function(_,s)writes=writes+1;lines[#lines+1]=s;return true end,
        flush=function()flushes=flushes+1;return true end,close=function()closes=closes+1;return true end}
end}
local log=SessionLog.new(loader,false)
log.once('startup',{text='中文\\"\n'});local before=writes
log.once('startup',{});assert(writes==before,'once repeats must not write or flush')
assert(opens==1 and writes==2,'header plus startup only')
log.once('fault',{reason='x'});log.once('fault',{reason='x'})
assert(writes==3,'fault writes once')
log.close();assert(closes==1 and flushes>=3)
return table.concat(lines)
