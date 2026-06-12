"""Rig the extracted Luke Skywalker (ROTJ) onto the shared animated skeleton.

Source: parts exported from the player's asset pack into /tmp/char_luke
(OBJ meshes + PNG textures + manifest.json). Luke's bind pose nearly matches
the Kyle skeleton rest pose, so the fit is a light analytic alignment followed
by a weight transfer from Kyle's meshes. A procedural saber (hilt + blade
named "luke_blade") is bound to the right hand for the game to recolor.

Run from starwars-duel/ :  python3 tools/build_luke_rig.py
Requires:  pip install bpy==4.5.10  and /tmp/char_luke from tree_export.py
"""
import bpy, mathutils, math, json, os

SRC = "/tmp/char_luke"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "characters", "luke.glb")
SKIP_PARTS = {"VolumetricLine green", "Sphere (1)", "pasted__pCube6", "pCylinder1"}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='assets/models/characters/jedi.glb')
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.animation_data_clear()
kyle_meshes = [o for o in bpy.data.objects if o.type == 'MESH']
drop = [o for o in kyle_meshes if any(k in o.name for k in
        ('Hair', 'Beard', 'Mustache', 'lightblade', 'P1_low', 'P2_low', 'Icosphere'))]
for o in drop:
    kyle_meshes.remove(o)
    bpy.data.objects.remove(o, do_unlink=True)

# ---- import Luke parts with their textures
man = json.load(open(os.path.join(SRC, "manifest.json")))
luke_parts = []
for part in man["parts"]:
    if part["name"] in SKIP_PARTS or not part["mesh_file"]:
        continue
    bpy.ops.wm.obj_import(filepath=os.path.join(SRC, part["mesh_file"]))
    objs = list(bpy.context.selected_objects)
    if not objs:
        continue
    o = objs[0]
    o.name = "luke_" + part["name"]
    if part["tex_file"]:
        m = bpy.data.materials.new("M_" + part["name"])
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.75
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(SRC, part["tex_file"]))
        if max(tex.image.size) > 768:
            tex.image.scale(768, 768)
        tex.image.pack()
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        o.data.materials.clear()
        o.data.materials.append(m)
    luke_parts.append(o)
print("LUKE PARTS:", [o.name for o in luke_parts])

# the OBJ importer may rotate for Z-up; normalize transforms
for o in luke_parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = luke_parts[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ---- measure the body to align the skeleton
body = next(o for o in luke_parts if "mat_body" in o.name)
def wv(o):
    M = o.matrix_world
    return [M @ v.co for v in o.data.vertices]
pts = wv(body)
def cluster(pred, pool):
    sel = [p for p in pool if pred(p)]
    if not sel:
        return None
    s = mathutils.Vector((0, 0, 0))
    for p in sel:
        s += p
    return s / len(sel)

# facing check: hands tell the lateral axis; eyes are on the front
eye = next(o for o in luke_parts if "mat_eye" in o.name)
eye_c = sum(wv(eye), mathutils.Vector()) / len(eye.data.vertices)
print("MEASURE eye center", [round(v, 2) for v in eye_c])

lhand = cluster(lambda p: p.x > 0.3 and 0.9 < p.z < 1.25, pts)
rhand = cluster(lambda p: p.x < -0.3 and 0.9 < p.z < 1.25, pts)
lelb = cluster(lambda p: 0.28 < p.x < 0.42 and 1.15 < p.z < 1.4, pts)
relb = cluster(lambda p: -0.42 < p.x < -0.28 and 1.15 < p.z < 1.4, pts)
lfoot = cluster(lambda p: p.z < 0.12 and p.x > 0.02, pts)
rfoot = cluster(lambda p: p.z < 0.12 and p.x < -0.02, pts)
lknee = cluster(lambda p: 0.42 < p.z < 0.55 and p.x > 0.02, pts)
rknee = cluster(lambda p: 0.42 < p.z < 0.55 and p.x < -0.02, pts)
print("MEASURE lhand", lhand, "rhand", rhand)
print("MEASURE lfoot", lfoot, "rfoot", rfoot)

# ---- pose the skeleton into Luke's bind pose (analytic two-bone)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
pb = arm.pose.bones
for b in pb:
    b.matrix_basis = mathutils.Matrix.Identity(4)
bpy.context.view_layer.update()
Mi_arm = arm.matrix_world.inverted()

def aim(bone, target_world):
    b = pb['mixamorig:' + bone]
    tgt = Mi_arm @ target_world
    head = b.head.copy()
    cur = (b.tail - b.head).normalized()
    new = (tgt - head).normalized()
    q = cur.rotation_difference(new)
    M = (mathutils.Matrix.Translation(head) @ q.to_matrix().to_4x4()
         @ mathutils.Matrix.Translation(-head))
    b.matrix = M @ b.matrix
    bpy.context.view_layer.update()

def two_bone(root, mid, tip, target_world, hint_world):
    rb, mb, tb = pb['mixamorig:' + root], pb['mixamorig:' + mid], pb['mixamorig:' + tip]
    S = arm.matrix_world @ rb.head
    L1 = (mb.head - rb.head).length * arm.matrix_world.to_scale().x
    L2 = (tb.head - mb.head).length * arm.matrix_world.to_scale().x
    W = target_world
    d = min((W - S).length, (L1 + L2) * 0.999)
    axis_n = (W - S).normalized()
    a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    base = S + axis_n * a
    hint_v = hint_world - base
    perp = hint_v - axis_n * hint_v.dot(axis_n)
    perp = perp.normalized() if perp.length > 1e-5 else mathutils.Vector((0, -1, 0))
    E = base + perp * h
    aim(root, E)
    aim(mid, W)

two_bone('LeftArm', 'LeftForeArm', 'LeftHand', lhand, lelb if lelb else lhand + mathutils.Vector((0, 0.2, 0.2)))
two_bone('RightArm', 'RightForeArm', 'RightHand', rhand, relb if relb else rhand + mathutils.Vector((0, 0.2, 0.2)))
two_bone('LeftUpLeg', 'LeftLeg', 'LeftFoot', lfoot + mathutils.Vector((0, 0, 0.07)), lknee + mathutils.Vector((0, -0.5, 0)))
two_bone('RightUpLeg', 'RightLeg', 'RightFoot', rfoot + mathutils.Vector((0, 0, 0.07)), rknee + mathutils.Vector((0, -0.5, 0)))
for side, tgt in (('Left', lhand), ('Right', rhand)):
    got = arm.matrix_world @ pb['mixamorig:' + side + 'Hand'].head
    print('POSE CHECK', side, 'wrist', [round(v, 3) for v in got], 'target', [round(v, 3) for v in tgt])
bpy.ops.object.mode_set(mode='OBJECT')

# ---- bake posed Kyle proxy, freeze pose as rest
def select_only(objs, active):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active

select_only(kyle_meshes, kyle_meshes[0])
bpy.ops.object.duplicate()
bpy.ops.object.join()
proxy = bpy.context.view_layer.objects.active
proxy.name = 'KyleProxy'
for m in list(proxy.modifiers):
    if m.type == 'ARMATURE':
        bpy.ops.object.modifier_apply(modifier=m.name)
for o in kyle_meshes:
    bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
print('POSE APPLIED')

# ---- weight transfer from the posed proxy to every Luke part
for o in luke_parts:
    select_only([o, proxy], proxy)
    bpy.ops.object.data_transfer(data_type='VGROUP_WEIGHTS',
        vert_mapping='POLYINTERP_NEAREST',
        layers_select_src='ALL', layers_select_dst='NAME',
        mix_mode='REPLACE')
    select_only([o], o)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    nz = sum(1 for v in o.data.vertices if sum(g.weight for g in v.groups) > 0.05)
    print('TRANSFER', o.name, nz, '/', len(o.data.vertices))
    select_only([o, arm], arm)
    bpy.ops.object.parent_set(type='ARMATURE_NAME')

# head/hair/eyes/teeth ride the head bone rigidly (transfer can smear them)
Mw = arm.matrix_world
for o in luke_parts:
    if any(k in o.name for k in ('head_shader', 'm_hair', 'mat_eye', 'teeth')):
        for g in list(o.vertex_groups):
            o.vertex_groups.remove(g)
        vg = o.vertex_groups.new(name='mixamorig:Head')
        vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')

bpy.data.objects.remove(proxy, do_unlink=True)

# ---- procedural saber in the right hand: hilt + blade ("luke_blade")
hand_b = arm.data.bones['mixamorig:RightHand']
hand_head = Mw @ hand_b.head_local
hand_tail = Mw @ hand_b.tail_local
grip_dir = (hand_tail - hand_head).normalized()
grip_c = hand_head + grip_dir * 0.07

def add_cyl(name, radius, depth, center, mat_color, emissive=False):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=center, vertices=12)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = grip_dir.to_track_quat('Z', 'Y')
    m = bpy.data.materials.new(name + "_mat")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*mat_color, 1)
    if emissive:
        bsdf.inputs["Emission Color"].default_value = (*mat_color, 1)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    else:
        bsdf.inputs["Metallic"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.3
    o.data.materials.append(m)
    select_only([o], o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    select_only([o, arm], arm)
    bpy.ops.object.parent_set(type='ARMATURE_NAME')
    vg = o.vertex_groups.get('mixamorig:RightHand') or o.vertex_groups.new(name='mixamorig:RightHand')
    vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
    return o

hilt = add_cyl("luke_hilt", 0.022, 0.26, grip_c, (0.35, 0.36, 0.4))
blade = add_cyl("luke_blade", 0.015, 0.92, grip_c + grip_dir * (0.13 + 0.46), (0.4, 1.0, 0.5), emissive=True)
luke_parts += [hilt, blade]

# ---- keep the animation library
ad = arm.animation_data or arm.animation_data_create()
for act in bpy.data.actions:
    if act.name.startswith(('DEL_', 'FIX_', '_')):
        continue
    tr = ad.nla_tracks.new()
    tr.name = act.name
    tr.strips.new(act.name, int(act.frame_range[0]), act)

select_only([arm] + luke_parts, arm)
bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), use_selection=True,
    export_animation_mode='ACTIONS',
    export_skins=True, export_def_bones=False,
    export_image_format='AUTO', export_yup=True)
print('EXPORTED', OUT)
