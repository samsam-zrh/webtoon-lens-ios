"""Export selected assets from the Unity build: meshes as OBJ, textures as
PNG, audio as WAV. Usage: python3 unity_export.py <name_filter> [name_filter...]
Exports anything whose asset name contains one of the filters (case-insens.)."""
import UnityPy
import os, sys

DATA = "/tmp/pack_x/Star Wars Virtual Museum_Data"
OUT = "/tmp/exported"
os.makedirs(OUT, exist_ok=True)
filters = [f.lower() for f in sys.argv[1:]]

def want(name: str) -> bool:
    n = (name or "").lower()
    return any(f in n for f in filters)

files = [os.path.join(DATA, f) for f in os.listdir(DATA)
         if os.path.isfile(os.path.join(DATA, f))
         and (f.startswith("level") and not f.endswith(".resS") or f.endswith(".assets"))]

n_mesh = n_tex = n_audio = 0
for p in sorted(files):
    try:
        env = UnityPy.load(p)
    except Exception:
        continue
    for obj in env.objects:
        t = obj.type.name
        if t not in ("Mesh", "Texture2D", "AudioClip"):
            continue
        try:
            d = obj.read()
            name = d.m_Name or "unnamed"
            if not want(name):
                continue
            safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in name)
            if t == "Mesh":
                obj_text = d.export()
                with open(f"{OUT}/{safe}_{obj.path_id}.obj", "w") as fh:
                    fh.write(obj_text)
                n_mesh += 1
            elif t == "Texture2D":
                img = d.image
                img.save(f"{OUT}/{safe}_{obj.path_id}.png")
                n_tex += 1
            elif t == "AudioClip":
                for cname, cdata in d.samples.items():
                    with open(f"{OUT}/{safe}_{obj.path_id}.wav", "wb") as fh:
                        fh.write(cdata)
                n_audio += 1
        except Exception as e:
            print("ERR", t, name if 'name' in dir() else '?', e)

print(f"exported: {n_mesh} meshes, {n_tex} textures, {n_audio} audio -> {OUT}")
