"""Inventory a Unity build's assets: meshes, textures, audio, by name."""
import UnityPy
import os, sys
from collections import Counter

DATA = "/tmp/pack_x/Star Wars Virtual Museum_Data"

files = []
for f in os.listdir(DATA):
    p = os.path.join(DATA, f)
    if os.path.isfile(p) and (f.startswith("level") and not f.endswith(".resS")
                              or f.endswith(".assets") or f == "globalgamemanagers"):
        files.append(p)

type_counts = Counter()
meshes, textures, audio = [], [], []
for p in sorted(files):
    try:
        env = UnityPy.load(p)
    except Exception as e:
        print("SKIP", os.path.basename(p), e)
        continue
    for obj in env.objects:
        t = obj.type.name
        type_counts[t] += 1
        try:
            if t == "Mesh":
                d = obj.read()
                meshes.append((d.m_Name, getattr(d, "m_VertexData", None) and len(d.m_VertexData.m_DataSize) or 0, os.path.basename(p)))
            elif t == "Texture2D":
                d = obj.read()
                textures.append((d.m_Name, d.m_Width, d.m_Height, os.path.basename(p)))
            elif t == "AudioClip":
                d = obj.read()
                audio.append((d.m_Name, os.path.basename(p)))
        except Exception:
            pass

print("=== TYPES ===")
for t, c in type_counts.most_common(15):
    print(f"{c:6d}  {t}")
print(f"\n=== MESHES ({len(meshes)}) ===")
for n, sz, src in sorted(meshes, key=lambda x: -x[1])[:120]:
    print(f"{sz:>10}  {n}   [{src}]")
print(f"\n=== AUDIO ({len(audio)}) ===")
for n, src in audio[:60]:
    print(f"  {n}   [{src}]")
print(f"\n=== BIG TEXTURES ({len(textures)}) ===")
for n, w, h, src in sorted(textures, key=lambda x: -(x[1]*x[2]))[:40]:
    print(f"{w:>5}x{h:<5}  {n}   [{src}]")
