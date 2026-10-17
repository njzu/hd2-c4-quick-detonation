"""Read final packages and independently rebuild extracted source; never deploy."""
import json,struct,subprocess,sys,zipfile
from pathlib import Path
import check,build
from archive import read_resource,resource_hash

def main():
    manifest=json.loads((build.OUT/'构建清单.json').read_text(encoding='utf-8'))
    results={}
    for kind in ('Release','Diagnostic'):
        item=manifest[kind];p=build.OUT/item['file'];assert build.sha(p)==item['sha256']
        with zipfile.ZipFile(p)as z:
            assert z.testzip()is None
            meta=json.loads(z.read('manifest.json'));assert meta['Guid']=='6b75c845-e898-4994-a747-38cdfe31be25'
            payload=z.read('9ba626afa44a3aa3.patch_0')
            assert struct.unpack_from('<I',payload,8)[0]==1
            raw=read_resource(payload,resource_hash('mods/zj/c4_quick_daily'))
            length,encoding=struct.unpack('<II',raw[:8]);body=raw[8:]
            assert len(body)==length and encoding==2
            expected=build.entry(kind=='Diagnostic')[0].encode('utf-8')
            assert body==expected and not body.startswith((b'\xef\xbb\xbf',b'\x1b'))and b'\0'not in body
            check.GameLua().run(body.decode('utf-8'),False)
            assert not z.read('9ba626afa44a3aa3.patch_0.stream')and not z.read('9ba626afa44a3aa3.patch_0.gpu_resources')
            for name in ('安装与卸载.md','发布说明.md','短实机验收.md'):
                assert z.read(name)==(build.OUT/name).read_bytes()
        results[kind]={'sha256':build.sha(p),'single_resource':True,'entry_byte_identical':True,'crc_and_compile':True}
    source=build.OUT/manifest['Source']['file'];assert build.sha(source)==manifest['Source']['sha256']
    dest=build.ROOT/'work/日用版源码复现'
    assert not dest.exists(),'Use a fresh extraction directory; do not mix with existing files.'
    dest.mkdir()
    with zipfile.ZipFile(source)as z:
        assert z.testzip()is None
        for name in z.namelist():
            target=(dest/name).resolve();assert target.is_relative_to(dest.resolve()),'unsafe archive path'
        z.extractall(dest)
    for script in ('build.py','check.py'):
        result=subprocess.run([sys.executable,'-B',str(dest/'work/日用版源码'/script)],cwd=dest,text=True,
            encoding='utf-8',capture_output=True)
        assert result.returncode==0,result.stdout+result.stderr
        (build.BUILD/('复现-'+script+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
    for kind in ('Release','Diagnostic','Source'):
        original=build.OUT/manifest[kind]['file'];reproduced=dest/'outputs/正式交付'/manifest[kind]['file']
        assert original.read_bytes()==reproduced.read_bytes(),kind+' reproduction differs'
        results.setdefault(kind,{})['source_rebuild_byte_identical']=True
    results.update({'passed':True,'source_extraction':str(dest),'reproduced_tests_passed':True,'game_modified':False})
    (build.OUT/'交付复现核验.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(results,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
