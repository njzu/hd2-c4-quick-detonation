"""Summarize existing samples and preserve history; no game writes."""
import hashlib,json,re,sys,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'outputs/正式交付'
sha=lambda b:hashlib.sha256(b).hexdigest().upper()
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    path=ROOT/'outputs/M1.3实测分析/M1.3合并分析.json'
    analysis=json.loads(path.read_text(encoding='utf-8'))
    result={'source_sha256':sha(path.read_bytes()),'sample_count':0,'traces':{},'categories':{},
        'scope':'Existing six bounded traces only. Avatar active is not proof of reload. Switching traces may overlap throw/reload.',
        'limits':['No independent reload-only trace beyond trace2 overlap.','No complete all-posture, all-menu or multiplayer coverage.',
                  'bit111 is a conservative veto in captured layout, not a universal holster contract.']}
    for tid,trace in analysis['traces'].items():
        rows=trace['samples'];result['sample_count']+=len(rows)
        category='normal_throw_reload_control'if tid=='2'else'equip_window'if tid in('1','6')else'holster_window'
        counts={};set_count=0
        for row in rows:
            raw=bytes.fromhex(row['avatar_flags_raw']);flag=bool(raw[13]&128)
            set_count+=flag
            label='slot'+str(row.get('selected_slot'))
            if row.get('active_ability_id')==521 and row.get('native_action_active'):
                label+='_throw_released'if row.get('release')else'_throw_pre_release'
            if row.get('avatar_ability_active'):label+='_avatar_active_unclassified'
            c=counts.setdefault(label,{'samples':0,'bit111_set':0});c['samples']+=1;c['bit111_set']+=flag
            c=result['categories'].setdefault(category,{'samples':0,'bit111_set':0});c['samples']+=1;c['bit111_set']+=flag
        result['traces'][tid]={'classification':category,'samples':len(rows),'bit111_set':set_count,'distribution':counts}
    assert result['sample_count']==1152
    assert result['traces']['2']['bit111_set']==0,'normal control counterexample blocks adoption'
    (OUT/'过渡位分布.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    expected={}
    for line in(ROOT/'outputs/SHA256.txt').read_text(encoding='utf-8').splitlines():
        value,name=line.split(None,1);expected[name]=value
    light=json.loads((ROOT/'outputs/M1日志分析/轻量观察构建.json').read_text(encoding='utf-8'))
    expected[light['package']['file']]=light['package']['sha256']
    expected[light['source_zip']]=light['source_zip_sha256']
    expected.update({'M1.2/C4远程引爆-M1.2-0.2.0.zip':'8518503E108C24055752CCC226E3CEE96CFAB4DB67FD0E78EC7CDE12B9E58116',
        'M1.2/M1.2源码-0.2.0.zip':'FCD7463AA9D4AC10C877BA3BD03001032BAF6AB867C56999D5BE6C34F8340CBB',
        'M1.3/C4操作边界采集-M1.3-0.3.0.zip':'E0C4FBBF989FD5D243E7942883B9731232179E78A2C1BD15C48AE279874B27F4',
        'M1.3/M1.3源码-0.3.0.zip':'C4080C3AF605259EADBE16BEFA5804904E941FA57A91398C99B2EADE27799934'})
    history=[]
    for name,value in expected.items():
        p=ROOT/'outputs'/name;actual=sha(p.read_bytes());assert actual==value,name
        history.append({'file':name,'sha256':actual,'unchanged':True})
    sys.path.insert(0,str(ROOT/'参考mod/BingusSharedLoader-main/scripts'))
    from archive import read_resource,resource_hash
    key=resource_hash('mods/zj/c4_remote_m13')
    with zipfile.ZipFile(ROOT/'outputs/M1.3/C4操作边界采集-M1.3-0.3.0.zip')as z:
        frozen=read_resource(z.read('9ba626afa44a3aa3.patch_0'),key)
    game=Path('E:/SteamLibrary/steamapps/common/Helldivers 2')
    matches=[]
    for p in(game/'data').glob('9ba626afa44a3aa3.patch_*'):
        if not re.fullmatch(r'.*\.patch_\d+',p.name):continue
        found=read_resource(p.read_bytes(),key)
        if found is not None:matches.append({'path':str(p),'byte_identical':found==frozen,'sha256':sha(found)})
    audit={'historical_packages':history,'deployed_m13_matches':matches,
        'm13_deployment_matches':len(matches)==1 and matches[0]['byte_identical'],
        'game_dll_sha256':sha((game/'data/game/game.dll').read_bytes()),'game_modified':False}
    (OUT/'历史与部署只读核验.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'sample_count':result['sample_count'],'categories':result['categories'],
        'trace2':result['traces']['2'],'historical_packages':len(history),'m13_deployment_matches':audit['m13_deployment_matches'],
        'game_dll_sha256':audit['game_dll_sha256']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
