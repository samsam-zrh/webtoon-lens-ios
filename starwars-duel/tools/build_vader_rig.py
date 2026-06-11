"""Re-rig the static Sketchfab Darth Vader (Makeamo) onto the animated
Kyle Katarn skeleton (Mixamo rig from jedi.glb), so Vader plays every combat
animation of the roster. Run from starwars-duel/ with:  python3 tools/build_vader_rig.py
Requires:  pip install bpy==4.5.10

Pipeline: analytic two-bone IK fits the skeleton into Vader's authored guard
stance -> the guard pose becomes the rest pose -> skin weights are transferred
from a posed copy of Kyle's meshes -> modular armor islands are hand-curated
(pauldrons stay on the torso, gloves on the hands, saber on the right hand)
-> exported to assets/models/characters/vader.glb with all animations.
"""
import bpy, mathutils, math

OUT = '/home/user/webtoon-lens-ios/starwars-duel/assets/models/characters/vader.glb'
SCALE = 0.0104
ROT_Z = 54.7

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='assets/models/characters/jedi.glb')
arm = next(o for o in bpy.data.objects if o.type=='ARMATURE')
arm.animation_data_clear()
kyle_meshes = [o for o in bpy.data.objects if o.type=='MESH']
# drop hair/face/blade props from the weight source; keep body/clothes
drop = [o for o in kyle_meshes if any(k in o.name for k in ('Hair','Beard','Mustache','Face','lightblade','P1_low','P2_low','Icosphere'))]
for o in drop:
    kyle_meshes.remove(o)
    bpy.data.objects.remove(o, do_unlink=True)

bpy.ops.import_scene.gltf(filepath='assets/models/vader/scene.gltf')
emp = bpy.data.objects.new('VaderRoot', None)
bpy.context.scene.collection.objects.link(emp)
known = set(kyle_meshes) | {arm, emp}
for o in bpy.data.objects:
    if o.parent is None and o not in known:
        o.parent = emp
emp.scale = (SCALE,)*3
emp.rotation_euler = (0,0,math.radians(ROT_Z))
bpy.context.view_layer.update()

body = bpy.data.objects['DARTH_Sabel vit_0']
def world_verts(o):
    M = o.matrix_world
    return [M @ v.co for v in o.data.vertices]
wv = world_verts(body)
acc = mathutils.Vector((0,0,0)); n=0
for w in wv:
    if 0.3 < w.z < 1.1: acc += w; n += 1
c = acc/n
emp.location = -mathutils.Vector((c.x, c.y, 0))
bpy.context.view_layer.update()
wv = world_verts(body)

def cluster(pred):
    pts = [w for w in wv if pred(w)]
    if not pts: return None
    s = mathutils.Vector((0,0,0))
    for p in pts: s += p
    return s/len(pts)

lhand = cluster(lambda w: w.y < -0.15 and 0.95 < w.z < 1.35 and w.x >= 0.0)
rhand = cluster(lambda w: w.y < -0.15 and 0.95 < w.z < 1.35 and w.x < 0.0)
lelb  = cluster(lambda w: w.x > 0.16 and 1.0 < w.z < 1.35 and w.y > -0.18)
relb  = cluster(lambda w: w.x < -0.16 and 1.0 < w.z < 1.35 and w.y > -0.18)
lfoot = cluster(lambda w: w.z < 0.14 and w.x >= 0.0)
rfoot = cluster(lambda w: w.z < 0.14 and w.x < 0.0)
lknee = cluster(lambda w: 0.4 < w.z < 0.55 and w.x >= 0.0)
rknee = cluster(lambda w: 0.4 < w.z < 0.55 and w.x < 0.0)
# saber grip: put the right wrist right on the hilt so the blade stays in hand
hilt = bpy.data.objects['DARTH_darthvader_VaderBodyArmourmat_0']
gs = mathutils.Vector((0,0,0))
gv = world_verts(hilt)
for p in gv: gs += p
grip_c = gs/len(gv)

helm = bpy.data.objects['DARTH_darthvader_VaderCapemat_0']
hs = mathutils.Vector((0,0,0))
hv = world_verts(helm)
for p in hv: hs += p
helm_c = hs/len(hv)

def add_empty(name, loc):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    bpy.context.scene.collection.objects.link(e)
    return e

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
pb = arm.pose.bones
# clear any lingering imported pose: back to the rest A-pose
for b in pb:
    b.matrix_basis = mathutils.Matrix.Identity(4)
bpy.context.view_layer.update()

Mi_arm = arm.matrix_world.inverted()
def aim(bone, target_world):
    """Rotate pose bone so it points from its head toward the target."""
    b = pb['mixamorig:'+bone]
    tgt = Mi_arm @ target_world
    head = b.head.copy()
    cur = (b.tail - b.head).normalized()
    new = (tgt - head).normalized()
    q = cur.rotation_difference(new)
    M = (mathutils.Matrix.Translation(head) @ q.to_matrix().to_4x4()
         @ mathutils.Matrix.Translation(-head))
    b.matrix = M @ b.matrix
    bpy.context.view_layer.update()

# two-bone analytic IK: place elbow/knee on the reachable circle nearest hint
def two_bone(root, mid, tip, target_world, hint_world):
    rb, mb, tb = pb['mixamorig:'+root], pb['mixamorig:'+mid], pb['mixamorig:'+tip]
    S = arm.matrix_world @ rb.head
    L1 = (mb.head - rb.head).length * arm.matrix_world.to_scale().x
    L2 = (tb.head - mb.head).length * arm.matrix_world.to_scale().x
    W = target_world
    d = (W - S).length
    d = min(d, (L1 + L2) * 0.999)
    axis_n = (W - S).normalized()
    a = (L1*L1 - L2*L2 + d*d) / (2*d)
    h2 = max(L1*L1 - a*a, 0.0)
    h = math.sqrt(h2)
    base = S + axis_n * a
    # perpendicular direction toward the hint
    hint_v = hint_world - base
    perp = (hint_v - axis_n * hint_v.dot(axis_n))
    perp = perp.normalized() if perp.length > 1e-5 else mathutils.Vector((0,-1,0))
    E = base + perp * h
    aim(root, E)
    aim(mid, W)

print('TARGETS lhand', lhand, 'rhand', rhand)
two_bone('LeftArm','LeftForeArm','LeftHand', lhand, lelb)
two_bone('RightArm','RightForeArm','RightHand', grip_c + (rhand - grip_c) * 0.35, relb)
two_bone('LeftUpLeg','LeftLeg','LeftFoot', lfoot + mathutils.Vector((0,0,0.07)), lknee + mathutils.Vector((0,-0.6,0)))
two_bone('RightUpLeg','RightLeg','RightFoot', rfoot + mathutils.Vector((0,0,0.07)), rknee + mathutils.Vector((0,-0.6,0)))
# feet flat on the ground pointing forward
for side, foot in (('Left', lfoot), ('Right', rfoot)):
    fb = pb['mixamorig:'+side+'Foot']
    toe = arm.matrix_world @ fb.head + mathutils.Vector((0,-0.16,-0.05))
    aim(side+'Foot', toe)
sp = pb['mixamorig:Spine']
sp.matrix_basis = sp.matrix_basis @ mathutils.Euler((math.radians(8),0,0)).to_matrix().to_4x4()
bpy.context.view_layer.update()
# verify wrists landed on their targets
for side, tgt in (('Left', lhand), ('Right', grip_c + (rhand - grip_c) * 0.35)):
    got = arm.matrix_world @ pb['mixamorig:'+side+'Hand'].head
    print('POSE CHECK', side, 'wrist', [round(v,3) for v in got], 'target', [round(v,3) for v in tgt])
bpy.ops.object.mode_set(mode='OBJECT')

# ---- bake a posed Kyle proxy (weights intact) BEFORE applying rest pose
def select_only(objs, active):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = active

select_only(kyle_meshes, kyle_meshes[0])
bpy.ops.object.duplicate()
dups = list(bpy.context.selected_objects)
bpy.ops.object.join()
proxy = bpy.context.view_layer.objects.active
proxy.name = 'KyleProxy'
# bake current (guard) pose into the proxy mesh
for m in list(proxy.modifiers):
    if m.type == 'ARMATURE':
        bpy.ops.object.modifier_apply(modifier=m.name)
# delete original kyle meshes
for o in kyle_meshes:
    bpy.data.objects.remove(o, do_unlink=True)

# now freeze the guard pose as the rest pose
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')

# lift neck/head into the helmet
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
Mi = arm.matrix_world.inverted()
head_t = Mi @ mathutils.Vector((helm_c.x, helm_c.y, helm_c.z - 0.06))
top_t  = Mi @ mathutils.Vector((helm_c.x, helm_c.y, helm_c.z + 0.18))
eb['mixamorig:Head'].head = head_t
eb['mixamorig:Neck'].tail = head_t
eb['mixamorig:Head'].tail = top_t
tb = eb.get('mixamorig:HeadTop_End')
if tb is not None:
    tb.head = top_t; tb.tail = top_t + mathutils.Vector((0,0,10))
bpy.ops.object.mode_set(mode='OBJECT')
print('POSE APPLIED')

# ---- weight transfer from posed Kyle proxy
transfer_meshes = ['DARTH_Sabel vit_0', 'DARTH_darthvader_VaderConsolesFlickermat_0']
manual = {
    'DARTH_darthvader_VaderCapemat_0': 'mixamorig:Head',
    'DARTH_darthvader_VaderHelmetRimmat_0': 'mixamorig:Spine2',
    'DARTH_darthvader_VaderBodyArmourmat_0': 'mixamorig:RightHand',
    'DARTH_Laser_0': 'mixamorig:RightHand',
    'DARTH_Sabel svart_0': 'mixamorig:RightHand',
}
allm = transfer_meshes + list(manual.keys())
for name in allm:
    o = bpy.data.objects[name]
    select_only([o], o)
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

for name in transfer_meshes:
    o = bpy.data.objects[name]
    select_only([o, proxy], proxy)   # transfer FROM active TO selected
    bpy.ops.object.data_transfer(data_type='VGROUP_WEIGHTS',
        vert_mapping='POLYINTERP_NEAREST',
        layers_select_src='ALL', layers_select_dst='NAME',
        mix_mode='REPLACE')
    if 'Consoles' in name:
        # cape/skirt must not follow arms
        for g in list(o.vertex_groups):
            if any(k in g.name for k in ('Shoulder','Arm','ForeArm','Hand')):
                o.vertex_groups.remove(g)
    else:
        # The arms rest against the chest, so nearest-surface transfer leaks
        # chest weights onto them. Segment the modular mesh into connected
        # islands, vote each island between body-part chains, and rebuild
        # weights for arm islands from their own chain.
        def seg_dist(p, a, b):
            ab = b - a
            t = 0.0 if ab.length_squared < 1e-9 else max(0.0, min(1.0, (p-a).dot(ab)/ab.length_squared))
            return (a + ab*t - p).length
        Mw = arm.matrix_world
        def segs_for(names, extend_last=0.0):
            out = []
            for bn in names:
                b = arm.data.bones[bn]
                h, t = Mw @ b.head_local, Mw @ b.tail_local
                out.append((bn, h, t))
            if extend_last > 0.0:
                bn, h, t = out[-1]
                out[-1] = (bn, h, t + (t-h).normalized()*extend_last)
            return out
        chains = {
            'Larm': segs_for(['mixamorig:LeftShoulder','mixamorig:LeftArm','mixamorig:LeftForeArm','mixamorig:LeftHand'], 0.10),
            'Rarm': segs_for(['mixamorig:RightShoulder','mixamorig:RightArm','mixamorig:RightForeArm','mixamorig:RightHand'], 0.10),
            'Lleg': segs_for(['mixamorig:LeftUpLeg','mixamorig:LeftLeg','mixamorig:LeftFoot'], 0.12),
            'Rleg': segs_for(['mixamorig:RightUpLeg','mixamorig:RightLeg','mixamorig:RightFoot'], 0.12),
            'spine': segs_for(['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2','mixamorig:Neck','mixamorig:Head']),
        }
        me = o.data
        parent_uf = list(range(len(me.vertices)))
        def find(a):
            while parent_uf[a] != a:
                parent_uf[a] = parent_uf[parent_uf[a]]; a = parent_uf[a]
            return a
        for e in me.edges:
            ra, rb = find(e.vertices[0]), find(e.vertices[1])
            if ra != rb: parent_uf[ra] = rb
        from collections import defaultdict
        islands = defaultdict(list)
        for i in range(len(me.vertices)):
            islands[find(i)].append(i)
        # Hand-curated island map (root vertex id -> binding), built from a
        # geometric survey of the 80 islands of this modular game mesh.
        SPINE2_RIGID = {6672,6827,6167,6552,6755,6715,6731,6743,4820,5132,
                        6598,6615,6564,5885,6342,5862,6315,4631,4734}
        RARM_CHAIN = {767,2043,3735,2687,1987,2645,1995}
        LARM_CHAIN = {4435,4351,4695}
        RHAND = {639,699}
        LHAND = {2101,2279,4515,463}
        def assign_rigid(vs, bone):
            vg = o.vertex_groups.get(bone) or o.vertex_groups.new(name=bone)
            for g in o.vertex_groups:
                if g != vg:
                    try: g.remove(vs)
                    except RuntimeError: pass
            vg.add(vs, 1.0, 'REPLACE')
        Mo = o.matrix_world
        rebuilt = 0
        for root, vs in islands.items():
            if root in SPINE2_RIGID:
                assign_rigid(vs, 'mixamorig:Spine2')
            elif root in RHAND:
                assign_rigid(vs, 'mixamorig:RightHand')
            elif root in LHAND:
                assign_rigid(vs, 'mixamorig:LeftHand')
            elif root in RARM_CHAIN or root in LARM_CHAIN:
                segs = chains['Rarm' if root in RARM_CHAIN else 'Larm']
                score = defaultdict(float)
                for i in vs:
                    p = Mo @ me.vertices[i].co
                    for bn, h, t in segs:
                        score[bn] += (1.0/(seg_dist(p,h,t)+0.02))**2
                assign_rigid(vs, max(score, key=score.get))
            else:
                continue
            rebuilt += len(vs)
        print('ISLAND CURATED REBUILD', name, rebuilt, 'verts in', len(islands), 'islands')
    select_only([o], o)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    nz = sum(1 for v in o.data.vertices if sum(g.weight for g in v.groups) > 0.05)
    print('TRANSFER', name, 'weighted:', nz, '/', len(o.data.vertices))
    select_only([o, arm], arm)
    bpy.ops.object.parent_set(type='ARMATURE_NAME')

for name, bone in manual.items():
    o = bpy.data.objects[name]
    select_only([o, arm], arm)
    bpy.ops.object.parent_set(type='ARMATURE_NAME')
    vg = o.vertex_groups.get(bone) or o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
    print('MANUAL BIND', name, '->', bone)

bpy.data.objects.remove(proxy, do_unlink=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o, do_unlink=True)

ad = arm.animation_data or arm.animation_data_create()
for act in bpy.data.actions:
    if act.name.startswith(('DEL_','FIX_','_')):
        continue
    tr = ad.nla_tracks.new(); tr.name = act.name
    tr.strips.new(act.name, int(act.frame_range[0]), act)

select_only([arm] + [bpy.data.objects[n] for n in allm], arm)
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True,
    export_animation_mode='ACTIONS',
    export_skins=True, export_def_bones=False,
    export_image_format='AUTO', export_yup=True)
print('EXPORTED', OUT)
