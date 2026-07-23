# -*- coding: utf-8 -*-
"""背景モデル制作の共通処理(Blender内で import して使う)。

パイプライン: 手続きマテリアルで組む → Smart UV → Cycles で
DIFFUSE(色のみ) を RGB に、EMIT を A(発光マスク) にベイク →
単一マテリアルへ差し替えて OBJ+MTL+PNG をエクスポート。
規約: 最大辺=1 で中心原点 / map_Kd はファイル名のみ(path_mode='STRIP')。
エンジン側は shaders/BackdropLayer.hlsl が albedo.a を発光マスクとして読む。

【向きの規約(重要)】エンジンはAssimpで軸変換なし=OBJ座標そのまま描画する
(カメラは -Z 側から +Z を見る)。このエクスポート設定(forward=-Z, up=Y)は
blender(x,y,z)→obj(x,z,-y) なので、**正面ディテールは blender +Y 側に作る**
(blender +Y → エンジン -Z = カメラ向き)。blender +Z 向きに作った面は
エンジンで上向き(寝る)になる。過去にこれを踏んで、エクスポート後の .obj を
頂点変換(det=+1の正回転)で直した: 正面+Y化=(x,y,z)→(-x,y,-z) /
寝た面をカメラ向き+天地保持=(x,y,z)→(-x,-z,-y)。
"""
import bpy
import numpy as np

# TimeArrow 配色(UI/既存モデルと同じ言語)
SLATE_D = (0.055, 0.062, 0.082, 1.0)   # 濃スレート #282c37 近辺(リニア)
SLATE_L = (0.16, 0.19, 0.27, 1.0)      # 明スレート #4a5063 近辺
CYAN = (0.11, 0.55, 1.0, 1.0)          # 時間シアン #5fc2ff
GOLD = (1.0, 0.62, 0.13, 1.0)          # 機構ゴールド #ffd24d
BONE = (0.55, 0.52, 0.45, 1.0)         # 風化した石の明部


def reset_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in list(block):
            if d.users == 0:
                block.remove(d)


def stone_material(name, base=SLATE_L, dark=SLATE_D, scale=6.0, crack=0.0, ao_mix=0.55):
    """風化した石。ノイズで2色を混ぜ、AOを乗算して彫りを焼き込む。crack>0でヒビの黒筋。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = scale
    noise.inputs['Detail'].default_value = 6.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = dark
    ramp.color_ramp.elements[1].color = base
    nt.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    ao = nt.nodes.new('ShaderNodeAmbientOcclusion')
    ao.inputs['Distance'].default_value = 0.25
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = ao_mix
    nt.links.new(ramp.outputs['Color'], mix.inputs['A'])
    nt.links.new(ao.outputs['Color'], mix.inputs['B'])
    out = mix.outputs['Result']
    if crack > 0.0:
        # ノイズ等高線の細筋を黒く落とす=ヒビ
        cn = nt.nodes.new('ShaderNodeTexNoise')
        cn.inputs['Scale'].default_value = scale * 0.7
        cn.inputs['Detail'].default_value = 4.0
        sub = nt.nodes.new('ShaderNodeMath'); sub.operation = 'SUBTRACT'
        sub.inputs[1].default_value = 0.5
        absn = nt.nodes.new('ShaderNodeMath'); absn.operation = 'ABSOLUTE'
        lt = nt.nodes.new('ShaderNodeMath'); lt.operation = 'LESS_THAN'
        lt.inputs[1].default_value = 0.012 * crack
        nt.links.new(cn.outputs['Fac'], sub.inputs[0])
        nt.links.new(sub.outputs[0], absn.inputs[0])
        nt.links.new(absn.outputs[0], lt.inputs[0])
        cmix = nt.nodes.new('ShaderNodeMix')
        cmix.data_type = 'RGBA'
        cmix.inputs['B'].default_value = (0.01, 0.01, 0.012, 1.0)
        nt.links.new(out, cmix.inputs['A'])
        nt.links.new(lt.outputs[0], cmix.inputs['Factor'])
        out = cmix.outputs['Result']
    nt.links.new(out, bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.9
    return m


def flat_material(name, color, rough=0.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = color
    b.inputs['Roughness'].default_value = rough
    return m


def glow_material(name, color, strength=1.0):
    """発光。EMITベイクでαマスクに落ち、エンジン側でパルス発光する。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = color
    b.inputs['Emission Color'].default_value = color
    b.inputs['Emission Strength'].default_value = strength
    return m


def bevel(obj, width=0.015, segments=1):
    mod = obj.modifiers.new('Bevel', 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = 0.9


def join_all(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target='MESH')  # モディファイア適用込み
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    return obj


def normalize(obj):
    """中心原点・最大辺=1 に正規化(既存モデル規約)。"""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    obj.location = (0, 0, 0)
    d = max(obj.dimensions)
    s = 1.0 / d
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bake_and_export(obj, out_dir, name, size=512):
    import os
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, f"{name}.png")

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')

    # boolean カッター由来の空スロットを埋める(node_tree None でベイクが落ちる)
    first = next(s.material for s in obj.material_slots if s.material)
    for slot in obj.material_slots:
        if slot.material is None:
            slot.material = first

    img = bpy.data.images.new(f"{name}_bake", size, size, alpha=True)
    for slot in obj.material_slots:
        nt = slot.material.node_tree
        node = nt.nodes.new('ShaderNodeTexImage')
        node.image = img
        nt.nodes.active = node

    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'CPU'
    scn.cycles.samples = 24
    scn.render.bake.margin = 6

    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
    rgb = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)[:, :, :3]
    bpy.ops.object.bake(type='EMIT')
    emit = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)[:, :, :3]
    mask = np.clip(emit.max(axis=2), 0.0, 1.0)

    out = np.empty((size, size, 4), dtype=np.float32)
    out[:, :, :3] = np.clip(rgb, 0.0, 1.0)
    out[:, :, 3] = mask
    img.pixels = out.ravel().tolist()
    img.filepath_raw = png
    img.file_format = 'PNG'
    img.save()

    # 単一マテリアル(ベイク画像)へ差し替えてからエクスポート
    obj.data.materials.clear()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    nt.links.new(tex.outputs['Color'], b.inputs['Base Color'])
    obj.data.materials.append(mat)

    bpy.ops.wm.obj_export(
        filepath=os.path.join(out_dir, f"{name}.obj"),
        export_selected_objects=True, export_materials=True,
        path_mode='STRIP', forward_axis='NEGATIVE_Z', up_axis='Y')
    return png
