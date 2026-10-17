-- Diagnostic build only. No ammo reader, projectile post-scan or trace ring.
local M={}
function M.new(log,api)
    local ffi=require('ffi')
    ffi.cdef[[int c4daily_QueryPerformanceCounter(int64_t *) __asm__("QueryPerformanceCounter");
        int c4daily_QueryPerformanceFrequency(int64_t *) __asm__("QueryPerformanceFrequency");]]
    local k=ffi.load('kernel32');local q=ffi.new('int64_t[1]');assert(k.c4daily_QueryPerformanceFrequency(q)~=0)
    local scale=1/tonumber(q[0]);local self={reads=0,bytes=0,n=0,total=0,max=0,stages={},samples={}}
    function self.clock()assert(k.c4daily_QueryPerformanceCounter(q)~=0);return tonumber(q[0])*scale end
    local start=self.clock();local due=start+10;local old=api.read
    api.read=function(at,n)self.reads=self.reads+1;self.bytes=self.bytes+n;return old(at,n)end
    function self.stage(name,seconds)
        if self.failed then return end
        local x=self.stages[name]or{n=0,total=0,max=0};self.stages[name]=x
        x.n=x.n+1;x.total=x.total+seconds;x.max=math.max(x.max,seconds)
    end
    function self.frame(frame,seconds)
        if self.failed then return end
        self.n=self.n+1;self.total=self.total+seconds;self.max=math.max(self.max,seconds)
        self.samples[(self.n-1)%2048+1]=seconds
        if self.clock()<due then return end
        local sorted={};for i=1,math.min(self.n,2048)do sorted[i]=self.samples[i]end;table.sort(sorted)
        local row={frame_id=frame,frames=self.n,mean_us=self.total/self.n*1e6,max_us=self.max*1e6,
            p95_us=sorted[math.ceil(#sorted*.95)]*1e6,p99_us=sorted[math.ceil(#sorted*.99)]*1e6,
            reads_per_frame=self.reads/self.n,bytes_per_frame=self.bytes/self.n,
            cost_scope='before_plus_after_excludes_original_update_and_this_flush',previous_flush_us=self.flush_us,
            previous_flush_frame=self.flush_frame}
        for name,x in pairs(self.stages)do row[name..'_mean_us']=x.total/x.n*1e6;row[name..'_max_us']=x.max*1e6 end
        local at=self.clock();local ok,why=pcall(function()log.event('performance',row);log.flush()end)
        if not ok then self.failed=tostring(why);self.stages={};self.samples={};return end
        self.flush_us=(self.clock()-at)*1e6;self.flush_frame=frame
        self.n=0;self.total=0;self.max=0;self.reads=0;self.bytes=0;self.stages={};self.samples={};due=self.clock()+10
    end
    return self
end
return M
