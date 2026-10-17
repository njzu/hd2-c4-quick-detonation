"""Verify daily candidate in isolated LuaJIT; no game process or game native calls."""
import ctypes as c
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
import build

def literal(text):return '"'+''.join('\\%03d'%b for b in text.encode('utf-8'))+'"'

class GameLua:
    def __init__(self):
        self.d=c.CDLL('E:/SteamLibrary/steamapps/common/Helldivers 2/bin/lua51.dll')
        d=self.d;d.luaL_newstate.restype=c.c_void_p;d.luaL_openlibs.argtypes=[c.c_void_p]
        d.luaL_loadbuffer.argtypes=[c.c_void_p,c.c_char_p,c.c_size_t,c.c_char_p]
        d.lua_pcall.argtypes=[c.c_void_p,c.c_int,c.c_int,c.c_int]
        d.lua_tolstring.argtypes=[c.c_void_p,c.c_int,c.c_void_p];d.lua_tolstring.restype=c.c_char_p
        d.lua_tonumber.argtypes=[c.c_void_p,c.c_int];d.lua_tonumber.restype=c.c_double
        d.lua_close.argtypes=[c.c_void_p]
    def run(self,text,execute=True,result_type='number'):
        d=self.d;s=d.luaL_newstate();d.luaL_openlibs(s)
        try:
            b=text.encode('utf-8');status=d.luaL_loadbuffer(s,b,len(b),b'=M12_offline')
            if not status and execute:status=d.lua_pcall(s,0,1,0)
            if status:raise AssertionError(d.lua_tolstring(s,-1,None).decode(errors='replace'))
            if execute and result_type=='text':return d.lua_tolstring(s,-1,None).decode('utf-8')
            return int(d.lua_tonumber(s,-1)) if execute else True
        finally:d.lua_close(s)


def prepare_fixture():
    dest=ROOT/'work/日用版测试'
    for name in ('src','scripts','tests'):
        shutil.copytree(build.UP/name,dest/name,dirs_exist_ok=True)
    for name in ('ContextReader.lua','SnapshotCache.lua'):
        shutil.copyfile(HERE/name,dest/'src'/name)
    spec=importlib.util.spec_from_file_location('daily_fixture_assemble',dest/'scripts/assemble.py')
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);m.assemble()
    subprocess.run([sys.executable,'-B','tests/make_native_fixture.py'],cwd=dest,capture_output=True,check=True)
    return dest

def prepare_catalog_fixture():
    dest=ROOT/'work/日用版签名测试'
    for folder in ('src','scripts','tests','private/tests'):(dest/folder).mkdir(parents=True,exist_ok=True)
    catalogs=build.catalogs();nodes={}
    for cat in catalogs:
        for node in cat['nodes']:
            if node['name'] in nodes:assert nodes[node['name']]==node
            nodes[node['name']]=node
    # Identical lifecycle functions have two names across the native/contact catalogs.
    # Put their code at one synthetic address, just as in the captured runtime.
    alias={};unique=[];by_signature={}
    for name,node in nodes.items():
        key=(node['hex'],str(node['mask']))
        if key in by_signature:
            canonical=by_signature[key];alias[name]=canonical['name']
            for ref in node.get('refs',[]):
                matches=[r for r in canonical['refs'] if r['at']==ref['at']]
                if not matches:canonical['refs'].append(ref.copy())
                elif 'symbol' in ref and 'symbol' not in matches[0]:matches[0].update(ref)
                elif 'symbol' in ref and ref['symbol']!=matches[0].get('symbol'):
                    alias[ref['symbol']]=matches[0]['symbol']
        else:
            import copy
            node=copy.deepcopy(node);unique.append(node);by_signature[key]=node
    for node in unique:
        if 'abilities' in node:
            import struct
            at=node['abilities']['capacity_offset']
            assert bytes.fromhex(node['mask'])[at:at+4]==bytes(4)
            raw=bytearray.fromhex(node['hex']);struct.pack_into('<I',raw,at,1023)
            node['hex']=raw.hex() # synthetic capacity; captured catalog keeps its masked immediate
        if node.get('from_symbol') in alias:node['from_symbol']=alias[node['from_symbol']]
        for ref in node.get('refs',[]):
            if ref.get('symbol') in alias:ref['symbol']=alias[ref['symbol']]
        for target in node.get('abilities',{}).get('targets',[]):
            if target['symbol'] in alias:target['symbol']=alias[target['symbol']]
    globals_=sorted({ref['symbol'] for node in unique for ref in node.get('refs',[])
        if 'symbol' in ref and ref['symbol'].startswith('global_')})
    cat={'nodes':unique,'fields':catalogs[0]['fields'],'required_globals':globals_}
    (dest/'src/native_catalog.json').write_text(json.dumps(cat),encoding='utf-8')
    for name in ('assemble.py','lua_packaging.py'):shutil.copyfile(build.UP/'scripts'/name,dest/'scripts'/name)
    shutil.copyfile(build.UP/'tests/make_native_fixture.py',dest/'tests/make_native_fixture.py')
    subprocess.run([sys.executable,'-B','tests/make_native_fixture.py'],cwd=dest,capture_output=True,check=True)
    return dest,catalogs

def main():
    lua=GameLua()
    for diagnostic in (False,True):lua.run(build.entry(diagnostic)[0],False)
    requests=lua.run(build.module('Requests')+(HERE/'test_requests.lua').read_text(encoding='utf-8'))
    log_text=lua.run(build.module('RollingLog')+build.module('SessionLog')+(HERE/'test_log.lua').read_text(encoding='utf-8'),result_type='text')
    log_rows=[json.loads(line)for line in log_text.splitlines()]
    assert len(log_rows)==3 and log_rows[1]['text']=='中文\\"\n'
    metrics=lua.run(build.module('Metrics')+(HERE/'test_metrics.lua').read_text(encoding='utf-8'))
    lifecycle={}
    names=('WindowsRead','ReadMemo','NativeResolver','ContextReader','SnapshotCache','FastReader',
        'WindowFocus','NativeUiGuard','GameplayGuard','AimInputState','RemoteReader','InstanceWrite','Idle520','SessionLog','Metrics')
    modules='\n'.join('local '+n+'=test_modules.'+n for n in names)+'\n'
    modules+=build.module('Requests')+build.module('RemoteAim')+build.module('ModeControl')
    for diagnostic in (False,True):
        mock=(HERE/'entry.lua.in').read_text(encoding='utf-8').replace('@@MODULES@@',modules).replace('@@DIAGNOSTICS@@',str(diagnostic).lower())
        for marker in ('NATIVE','CONTACT','ACTION'):mock=mock.replace('@@'+marker+'@@','{}')
        lifecycle[str(diagnostic)]=lua.run('local DIAG='+str(diagnostic).lower()+'\nlocal ENTRY='+literal(mock)+'\n'+(HERE/'test_entry.lua').read_text(encoding='utf-8'))
    stage=prepare_fixture();cwd=Path.cwd()
    try:
        os.chdir(stage)
        reader=lua.run('local READER_SOURCE='+literal((HERE/'RemoteReader.lua').read_text(encoding='utf-8'))+'\n'+(HERE/'test_reader.lua').read_text(encoding='utf-8'))
        fast=json.loads(lua.run('local FAST_SOURCE='+literal((HERE/'FastReader.lua').read_text(encoding='utf-8'))+'\nlocal IDLE_SOURCE='+literal((HERE/'Idle520.lua').read_text(encoding='utf-8'))+'\n'+(HERE/'test_fast.lua').read_text(encoding='utf-8'),result_type='text'))
        aim=json.loads(lua.run('local DIAGNOSTICS=true\nlocal OLD_SOURCE='+literal((HERE/'M12RemoteAim.lua').read_text(encoding='utf-8'))+'\nlocal NEW_SOURCE='+literal('local DIAGNOSTICS=true\n'+(HERE/'RemoteAim.lua').read_text(encoding='utf-8'))+'\nlocal INPUT_SOURCE='+literal((build.UP/'src/AimInputState.lua').read_text(encoding='utf-8'))+'\n'+(HERE/'test_aim_reuse.lua').read_text(encoding='utf-8'),result_type='text'))
    finally:os.chdir(cwd)
    # Real Windows page query and WPM exercise only memory owned by this isolated process.
    instance=lua.run(''.join(build.module(n)for n in ('WinApi','GuardSpans','PointerValue','ContextReader','WindowsRead','InstanceWrite','ModeControl'))+(HERE/'test_instance.lua').read_text(encoding='utf-8'))
    fixture,catalogs=prepare_catalog_fixture()
    try:
        os.chdir(fixture)
        code=build.module('GuardSpans')+build.module('NativeResolver')+'local NativeCatalog='+build.lua(catalogs[0])+'\nlocal RemoteCatalog='+build.lua(catalogs[1])+'\nlocal ActionCatalog='+build.lua(catalogs[2])+'\n'
        resolver=lua.run(code+(HERE/'test_catalog.lua').read_text(encoding='utf-8'))
    finally:os.chdir(cwd)
    release=build.entry(False)[0]
    for unwanted in ('QueryPerformanceCounter','local BoundaryTrace=','local AmmoEvidence=','local Telemetry=','local Metrics='):
        assert unwanted not in release,unwanted
    result={'passed':True,'request_assertions':requests,'target_reader_assertions':reader,'entry_assertions':lifecycle,
        'fast_reader':fast,'aim_reuse':aim,'resolver_assertions':resolver,'instance_writer_and_mode_assertions':instance,
        'diagnostic_metrics_assertions':metrics,
        'compile_game_luajit':['Release','Diagnostic'],'release_heavy_diagnostics_absent':True,
        'windows_own_buffer_write_test':True,'release_log_roundtrip_and_once':True,'game_process_modified':False,'game_native_actions_executed':False,
        'gameplay_verified':False,'multiplayer_verified':False}
    build.OUT.mkdir(parents=True,exist_ok=True)
    (build.OUT/'离线验证.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
