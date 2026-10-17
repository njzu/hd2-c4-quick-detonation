local records={};local flushed=0
local log={event=function(kind,row)records[#records+1]={kind=kind,row=row}end,flush=function()flushed=flushed+1 end}
local api={read=function(_,n)return string.rep('x',n)end}
local m=Metrics.new(log,api);local start=m.clock();m.clock=function()return start+11 end
api.read(1,8);m.stage('context',.0001);m.frame(1,.001)
assert(#records==1 and flushed==1 and records[1].row.mean_us==1000)
assert(records[1].row.reads_per_frame==1 and records[1].row.bytes_per_frame==8)
assert(records[1].row.context_mean_us==100 and records[1].row.previous_flush_us==nil)
log.flush=function()error('disk full')end;m.clock=function()return start+22 end;m.frame(2,.002)
assert(m.failed and #m.samples==0)
m.frame(3,.003);assert(#records==2,'failed diagnostic flush must not retry every frame')
return 5
