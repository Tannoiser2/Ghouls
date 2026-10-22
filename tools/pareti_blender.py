# Pareti delle fogne per Ghouls Reborn: dal disegno della tessera si ricava la zona di roccia (nero),
# Uso: python3 tools/pareti_blender.py [tessere…]   (serve il modulo bpy: pip install bpy opencv-python-headless)
# oppure: blender --background --python tools/pareti_blender.py -- croce curva
# Blender ne fa un solido alto H con i bordi smussati che segue esattamente il contorno dei corridoi.
import bpy, cv2, numpy as np, sys, os
S = 2.0        # lato della tessera nel gioco
H = 0.30       # altezza delle pareti
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = ROOT + '/assets/reborn/tiles/'
OUT = ROOT + '/assets/reborn/models/tiles/'
os.makedirs(OUT, exist_ok=True)

def rock_mask(path):
    im = cv2.imread(path)
    v = cv2.cvtColor(im, cv2.COLOR_BGR2HSV)[:, :, 2]
    dark = (v < 45).astype(np.uint8) * 255
    dark = cv2.morphologyEx(dark, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(dark)
    keep = np.zeros_like(dark)
    h, w = dark.shape
    for i in range(1, n):
        x, y, ww, hh, area = st[i]
        touches = x <= 2 or y <= 2 or x + ww >= w - 2 or y + hh >= h - 2
        if area > 2000 and touches:
            keep[lab == i] = 255
    # bordo di 1 px aperto: le pareti non si chiudono sul lato della tessera dove il vicino continua
    return keep

def build(kind):
    mask = rock_mask(SRC + kind + '.jpg')
    h, w = mask.shape
    pad = cv2.copyMakeBorder(mask, 2, 2, 2, 2, cv2.BORDER_REPLICATE)
    cnts, hier = cv2.findContours(pad, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    cu = bpy.data.curves.new(kind, 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    cu.extrude = H * 0.5
    cu.bevel_depth = 0.025
    cu.bevel_resolution = 2
    cu.resolution_u = 1
    for c in cnts:
        if cv2.contourArea(c) < 200:
            continue
        ap = cv2.approxPolyDP(c, 1.6, True).reshape(-1, 2).astype(float) - 2.0
        sp = cu.splines.new('POLY')
        sp.points.add(len(ap) - 1)
        for i, (x, y) in enumerate(ap):
            X = (x / (w - 1) - 0.5) * S
            Z = (y / (h - 1) - 0.5) * S
            sp.points[i].co = (X, -Z, 0, 1)   # Blender Y = -Z del gioco (glTF)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(kind, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location.z = H * 0.5 - 0.025
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.object.convert(target='MESH')
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = ob.data
    bpy.ops.object.shade_auto_smooth(angle=0.7)
    bpy.ops.export_scene.gltf(filepath=OUT + kind + '.glb', use_selection=True, export_format='GLB',
        export_apply=True, export_materials='NONE', export_yup=True)
    print(kind, len(me.vertices), 'vertici')
    bpy.data.objects.remove(ob)

bpy.ops.wm.read_factory_settings(use_empty=True)
kinds = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [f[:-4] for f in sorted(os.listdir(SRC)) if f.endswith('.jpg')]
for k in kinds:
    build(k)
