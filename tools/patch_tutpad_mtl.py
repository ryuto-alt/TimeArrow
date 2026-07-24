# patch_tutpad_mtl.py -- TutPad の MTL に単色テクスチャ(map_Kd)を追加する。
# エンジンの ModelLoader は MTL の Kd(拡散色)を読まずテクスチャのみ対応のため、
# Blender から OBJ を再エクスポートするたびに必ずこれを再実行すること。
import glob
import os

TEXMAP = {
    'PadBody': 'tex_body.png', 'PadDark': 'tex_dark.png',
    'PadBtnA': 'tex_btnA.png', 'PadBtnB': 'tex_btnB.png',
    'PadBtnX': 'tex_btnX.png', 'PadBtnY': 'tex_btnY.png',
    'PadBumper': 'tex_bumper.png',
}

base = os.path.join(os.path.dirname(__file__), '..', 'assets', 'models', 'TutPad')
for f in glob.glob(os.path.join(base, 'TutPad_*.mtl')):
    lines = open(f, encoding='utf-8').read().splitlines()
    out, cur = [], None
    changed = False
    for ln in lines:
        if ln.startswith('map_Kd'):
            continue                      # 旧行は貼り直す(重複防止)
        if ln.startswith('newmtl '):
            cur = ln.split(None, 1)[1].strip()
        out.append(ln)
        if ln.startswith('newmtl ') and cur in TEXMAP:
            out.append('map_Kd ' + TEXMAP[cur])
            changed = True
    open(f, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(os.path.basename(f), 'patched' if changed else 'no-op')
