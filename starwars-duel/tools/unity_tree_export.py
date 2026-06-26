"""Export a full character from the Unity build: walks the GameObject tree,
exports every renderer's mesh as OBJ + its main texture as PNG, and writes a
manifest.json with per-part transforms and texture pairing.

Usage: python3 tree_export.py "<root GameObject name>" <outdir>
"""
import UnityPy
import os, sys, json

DATA = "/tmp/pack_x/Star Wars Virtual Museum_Data"
ROOT_NAME = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

files = [os.path.join(DATA, f) for f in os.listdir(DATA)
         if os.path.isfile(os.path.join(DATA, f))
         and (f.startswith("level") and not f.endswith(".resS") or f.endswith(".assets"))]

def safe(s):
    return "".join(c if c.isalnum() or c in "._-" else "_" for c in (s or "x"))[:60]

manifest = {"root": ROOT_NAME, "parts": []}
n = 0

def tex_from_material(mat):
    try:
        props = mat.m_SavedProperties
        for entry in props.m_TexEnvs:
            key = entry[0] if isinstance(entry, (list, tuple)) else entry
            val = entry[1] if isinstance(entry, (list, tuple)) else props.m_TexEnvs[entry]
            kname = getattr(key, "string", None) or str(key)
            if "_MainTex" in kname or "BaseMap" in kname or "BaseColor" in kname:
                t = val.m_Texture
                if t and t.path_id:
                    return t.read()
    except Exception:
        pass
    return None

def export_renderer(go_name, renderer, depth):
    global n
    try:
        # mesh: SkinnedMeshRenderer has m_Mesh; MeshRenderer via MeshFilter on the GO
        mesh_ptr = getattr(renderer, "m_Mesh", None)
        mesh = mesh_ptr.read() if mesh_ptr and mesh_ptr.path_id else None
        if mesh is None:
            return
        part = {"name": go_name, "mesh_file": None, "tex_file": None}
        objtxt = mesh.export()
        mf = f"{safe(go_name)}_{n}.obj"
        with open(os.path.join(OUT, mf), "w") as fh:
            fh.write(objtxt)
        part["mesh_file"] = mf
        mats = getattr(renderer, "m_Materials", [])
        for mp in mats:
            if not mp.path_id:
                continue
            try:
                tex = tex_from_material(mp.read())
            except Exception:
                tex = None
            if tex is not None:
                tf = f"{safe(tex.m_Name)}_{n}.png"
                tex.image.save(os.path.join(OUT, tf))
                part["tex_file"] = tf
                break
        manifest["parts"].append(part)
        n += 1
        print("  part:", go_name, "->", part["mesh_file"], part["tex_file"])
    except Exception as e:
        print("  ERR", go_name, e)

def walk(transform, depth=0):
    try:
        go = transform.m_GameObject.read()
    except Exception:
        return
    name = go.m_Name
    for comp_ptr in go.m_Components:
        try:
            comp = comp_ptr.read()
        except Exception:
            continue
        tname = comp_ptr.type.name if hasattr(comp_ptr, "type") else type(comp).__name__
        if tname == "SkinnedMeshRenderer":
            export_renderer(name, comp, depth)
        elif tname == "MeshFilter":
            mesh_ptr = getattr(comp, "m_Mesh", None)
            if mesh_ptr and mesh_ptr.path_id:
                class R: pass
                r = R(); r.m_Mesh = mesh_ptr; r.m_Materials = []
                # find sibling MeshRenderer for materials
                for c2 in go.m_Components:
                    try:
                        cc = c2.read()
                        if c2.type.name == "MeshRenderer":
                            r.m_Materials = cc.m_Materials
                    except Exception:
                        pass
                export_renderer(name, r, depth)
    for child in transform.m_Children:
        try:
            walk(child.read(), depth + 1)
        except Exception:
            pass

found = False
for p in sorted(files):
    try:
        env = UnityPy.load(p)
    except Exception:
        continue
    for obj in env.objects:
        if obj.type.name != "GameObject":
            continue
        try:
            go = obj.read()
        except Exception:
            continue
        if go.m_Name != ROOT_NAME:
            continue
        print("FOUND root in", os.path.basename(p))
        found = True
        for comp_ptr in go.m_Components:
            try:
                comp = comp_ptr.read()
                if comp_ptr.type.name == "Transform":
                    walk(comp)
            except Exception as e:
                print("walk err", e)
        break
    if found:
        break

with open(os.path.join(OUT, "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=1)
print(f"DONE: {n} parts -> {OUT}")
