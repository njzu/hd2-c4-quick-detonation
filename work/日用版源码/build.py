"""Build daily Release and optional Diagnostic candidates. Does not deploy or start HD2."""
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
UP=ROOT/'work/上游源码'
OUT=ROOT/'outputs/正式交付'
BUILD=ROOT/'work/日用版构建'
sys.path.insert(0,str(ROOT/'参考mod/BingusSharedLoader-main/scripts'))
from archive import make_archive,resource_hash
from build_addon import entry_source
sys.path.insert(0,str(UP/'scripts'))
from assemble import lua,delivery_catalog

def subset(name,roots,required):
    cat=json.loads((UP/f'src/{name}_catalog.json').read_text(encoding='utf-8'))
    by={n['name']:n for n in cat['nodes']};selected=set()
    def visit(key):
        if key in selected:return
        selected.add(key);node=by[key]
        for ref in node.get('refs',[]):
            if ref.get('symbol') in by:visit(ref['symbol'])
        if node.get('from_symbol') in by:visit(node['from_symbol'])
        for target in node.get('abilities',{}).get('targets',[]):visit(target['symbol'])
    for key in roots:visit(key)
    result=delivery_catalog(dict(schema=cat.get('schema',1),fields=cat['fields'],
        required_globals=required,nodes=[n for n in cat['nodes'] if n['name'] in selected]))
    provided={n['name'] for n in result['nodes']}|{r['symbol'] for n in result['nodes'] for r in n.get('refs',[]) if 'symbol' in r}
    assert set(required)<=provided,(name,set(required)-provided)
    return result

def catalogs():
    native=subset('native',[
        'fn_player_primary','fn_inventory_selected','fn_entity_by_id','fn_ui_state','fn_ability_current',
        'fn_fire_flags_init','fn_ability_template','fn_weapon_functions','fn_input_mapping','fn_input_inhibit','fn_input_unblock',
        *['fn_flag_'+str(n)for n in(108,84,97,114,100,93,83,105,98,99,101,78,107,112,128,131,86)],
        'fn_low_pose_veto','fn_airborne_pose'],
        ['global_mode','global_player','global_inventory','global_owner','global_avatar','global_ui','global_ability','global_weapon_data','global_input_owner'])
    contact=subset('contact',['contact_remote_lifecycle','contact_remote_owner','contact_world_root'],
        ['global_contact_remote','global_contact_owner','global_contact_world','global_contact_explosive'])
    action=subset('native',['fn_start','fn_eligibility','fn_exclusion_gate'],
        ['global_fire_latch','global_blocker','global_exclusions'])
    assert all(n['name']not in('fn_consume','fn_after','fn_reload')for cat in(native,action)for n in cat['nodes'])
    return native,contact,action

def module(name):
    p=HERE/(name+'.lua')
    if not p.exists():p=UP/'src'/(name+'.lua')
    source=p.read_text(encoding='utf-8')
    return 'local '+name+'=(function()\n'+source+'\nend)()\n'

def entry(diagnostic=False):
    n,c,a=catalogs()
    names=['WinApi','GuardSpans','ReadMemo','NativeResolver','AvatarFlags','ContextReader','PointerValue','WindowsRead',
        'SnapshotCache','WindowFocus','NativeUiGuard','GameplayGuard','RollingLog','AimInputState','FastReader',
        'RemoteReader','RemoteAim','Requests','ModeControl','InstanceWrite','Idle520','SessionLog']
    if diagnostic:names.append('Metrics')
    text=(HERE/'entry.lua.in').read_text(encoding='utf-8').replace('@@DIAGNOSTICS@@','true'if diagnostic else'false')
    text=text.replace('@@MODULES@@',''.join(module(x)for x in names)).replace('@@NATIVE@@',lua(n)).replace('@@CONTACT@@',lua(c)).replace('@@ACTION@@',lua(a))
    assert '@@'not in text
    return text,n,c,a

def zip_write(path,files):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
        for name,b in sorted(files.items()):
            i=zipfile.ZipInfo(name,(2026,10,17,0,0,0));i.compress_type=zipfile.ZIP_DEFLATED;z.writestr(i,b)
    with zipfile.ZipFile(path)as z:assert z.testzip()is None and {n:z.read(n)for n in z.namelist()}==files

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def main():
    import struct
    OUT.mkdir(parents=True,exist_ok=True);BUILD.mkdir(parents=True,exist_ok=True)
    results={}
    for diagnostic in(False,True):
        text,n,c,a=entry(diagnostic);kind='Diagnostic'if diagnostic else'Release'
        (BUILD/(kind+'.lua')).write_text(text,encoding='utf-8',newline='\n')
        body=entry_source('mods/zj/c4_quick_daily',text.encode('utf-8'))
        manifest={'Version':1,'Guid':'6b75c845-e898-4994-a747-38cdfe31be25','Name':'C4 Quick 1.0.0-rc1 '+kind,
            'Description':'Native left throw, owner-batch right detonate; automatic DEPLOY via guarded instance field; idle native520 feedback, busy remote. Default mouse bindings. Requires Bingus Shared Loader v17+. Disable all old C4 addons. Candidate: live acceptance pending.','IconPath':None}
        files={'manifest.json':(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),
            'LICENSE.txt':(UP/'LICENSE').read_bytes(),
            '9ba626afa44a3aa3.patch_0':make_archive({resource_hash('mods/zj/c4_quick_daily'):struct.pack('<II',len(body),2)+body}),
            '9ba626afa44a3aa3.patch_0.stream':b'','9ba626afa44a3aa3.patch_0.gpu_resources':b''}
        for name in('安装与卸载.md','短实机验收.md','发布说明.md'):
            p=OUT/name
            if p.exists():files[name]=p.read_bytes()
        target=OUT/('诊断构建/C4快速引爆-1.0.0-rc1-Diagnostic.zip'if diagnostic else'C4快速引爆-1.0.0-rc1-Release.zip')
        target.parent.mkdir(parents=True,exist_ok=True);zip_write(target,files)
        results[kind]={'file':target.relative_to(OUT).as_posix(),'sha256':sha(target),'lua_bytes':len(body)}
    source={}
    for p in HERE.iterdir():
        if p.is_file()and p.name not in('configure_build.py','inspect_native.py'):source[p.relative_to(ROOT).as_posix()]=p.read_bytes()
    for folder in('src','scripts','tests'):
        for p in(UP/folder).rglob('*'):
            if p.is_file()and '__pycache__'not in p.parts:source[p.relative_to(ROOT).as_posix()]=p.read_bytes()
    for p in(UP/'LICENSE',ROOT/'参考mod/BingusSharedLoader-main/LICENSE',ROOT/'参考mod/BingusSharedLoader-main/scripts/archive.py',ROOT/'参考mod/BingusSharedLoader-main/scripts/build_addon.py',ROOT/'outputs/C4快速引爆完整收尾方案-v4.md'):
        source[p.relative_to(ROOT).as_posix()]=p.read_bytes()
    for name in('安装与卸载.md','短实机验收.md','发布说明.md'):
        p=OUT/name
        if p.exists():source[p.relative_to(ROOT).as_posix()]=p.read_bytes()
    source['README.txt']='Python 3.10+: python -B work/日用版源码/build.py; python -B work/日用版源码/check.py\nNo deployment. Tests use installed game lua51.dll in isolated process.\n'.encode('utf-8')
    target=OUT/'C4快速引爆-1.0.0-rc1-源码.zip';zip_write(target,source)
    results['Source']={'file':target.name,'sha256':sha(target)}
    results.update({'version':'1.0.0-rc1','native_nodes':len(n['nodes']),'contact_nodes':len(c['nodes']),'optional_action_nodes':len(a['nodes']),
        'plan_v4_sha256':sha(ROOT/'outputs/C4快速引爆完整收尾方案-v4.md'),'deployed':False,'live_acceptance':False,
        'auto_mode':'guarded_instance_word_pending_live','feedback':'strict_idle520_busy_remote_pending_live','transition':'conservative_bit111_current_layout'})
    (OUT/'构建清单.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'SHA256.txt').write_text(''.join(results[x]['sha256']+'  '+results[x]['file']+'\n'for x in('Release','Diagnostic','Source')),encoding='utf-8')
    print(json.dumps(results,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
