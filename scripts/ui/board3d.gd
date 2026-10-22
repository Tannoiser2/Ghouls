class_name Board3D
extends SubViewportContainer
## Vista 3D: le fogne sotto (tessere con le gallerie in rilievo, pile di pedine come standee) e la
## città sopra (i dieci Obiettivi su piedistalli tutt'intorno, collegati ai loro tombini da tubi luminosi).
## Trascina col sinistro per ruotare, col destro per spostare, rotella per lo zoom.
## Stessa interfaccia di MapView (segnali loc_clicked / tomb_clicked, allowed, source, ghost, focus).
## Se in assets/reborn/models/ ci sono ghoul.glb, volontario.glb o <obiettivo>.glb si usano quelli.

signal loc_clicked(loc: String)
signal tomb_clicked(loc: String, objkey: String)

const D = preload("res://scripts/data/gh_data.gd")
const S := 2.0                      # lato di una tessera
const WALL_H := 0.26
const CITY_Y := 0.45
const MODEL_YAW := 0.0
const SURF_Y := 2.6                 # altezza della «superficie» dove galleggiano i luoghi rivelati
const COL_STEP := 2.3
const MIN_GAP := 1.95

var eng: GHEngine
var view
var allowed: Dictionary = {}
var allowed_tombs: Dictionary = {}
var source := ""
var ghost: Array = []
var focus := ""

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var yaw := 0.0
var pitch := -58.0
var dist := 16.0
var target := Vector3.ZERO
var tiles_root: Node3D
var dyn: Node3D
var tile_nodes := {}               # chiave -> Node3D
var ring_r := 6.5
var bpos := {}                     # obiettivo -> Vector3 (centro del piedistallo)
var drag_btn := -1
var drag_from := Vector2.ZERO
var drag_moved := false
var pulse := 0.0
var hl_mats: Array = []
var mats := {}
var models := {}
var _fitted := false
var _dirty := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.own_world_3d = true
	vp.handle_input_locally = false
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#06080a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#7f8f74")
	e.ambient_light_energy = 0.32
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.08
	e.fog_enabled = true
	e.fog_light_color = Color("#0b0f08")
	e.fog_density = 0.012
	env.environment = e
	vp.add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-58, 28, 0)
	moon.light_energy = 1.0
	moon.light_color = Color("#e6efff")
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	vp.add_child(moon)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, -150, 0)
	fill.light_energy = 0.22
	fill.light_color = Color("#9fc0a0")
	vp.add_child(fill)
	var covo_light := OmniLight3D.new()
	covo_light.position = Vector3(0, 0.7, 0)
	covo_light.light_color = Color("#ff5a3c")
	covo_light.light_energy = 1.6
	covo_light.omni_range = 2.6
	vp.add_child(covo_light)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 300.0
	pivot.add_child(cam)
	# terreno della città
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(160, 160)
	ground.mesh = gm
	ground.position.y = -0.06
	ground.material_override = _mat("ground", Color("#0c0f0a"), 0.95)
	vp.add_child(ground)
	tiles_root = Node3D.new()
	vp.add_child(tiles_root)
	dyn = Node3D.new()
	vp.add_child(dyn)
	_load_models()
	_update_cam()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _fitted and not user_moved:
		fit.call_deferred()


func set_engine(e: GHEngine) -> void:
	eng = e
	redraw()


func queue_redraw_3d() -> void:
	redraw()


## Ricostruisce lo strato dinamico (pedine, evidenziazioni, tubi). Una volta per fotogramma.
func redraw() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


# ================================================================ materiali e modelli

func _mat(key: String, col: Color, rough := 0.8, metal := 0.0, emit := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit.a > 0:
		m.emission_enabled = true
		m.emission = Color(emit.r, emit.g, emit.b)
		m.emission_energy_multiplier = emit.a
	mats[key] = m
	return m


func _wall_mat() -> Material:
	if not mats.has("pareti"):
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/reborn/models/materials/pareti.gdshader")
		m.set_shader_parameter("mattoni", load("res://assets/reborn/models/materials/mattoni.jpg"))
		m.set_shader_parameter("roccia", load("res://assets/reborn/models/materials/roccia.jpg"))
		mats["pareti"] = m
	return mats["pareti"]


func _glow_mat(col: Color, alpha := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.set_meta("a", alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	hl_mats.append(m)
	return m


func _tex_mat(t: Texture2D, alpha := 1.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, alpha)
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _load_models() -> void:
	var names := ["ghoul", "ghoul_1", "ghoul_2", "ghoul_3", "ghoul_4", "ghoul_5", "volontario"]
	for k in D.OBJ_ORDER:
		names.append(k)
		names.append(k + "_dev")
	for n in names:
		var p := "res://assets/reborn/models/%s.glb" % n
		if UI.reborn and ResourceLoader.exists(p):
			models[n] = load(p)


## Istanza di un modello Reborn alta `height`; con `width` > 0 la pianta sta invece in un quadrato di quel lato.
func _model(n: String, height: float, width := 0.0) -> Node3D:
	if not models.has(n):
		return null
	var inst: Node3D = models[n].instantiate()
	var aabb := _aabb(inst)
	var sc := height / maxf(aabb.size.y, 0.001)
	if width > 0.0:
		sc = width / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
	var holder := Node3D.new()
	holder.add_child(inst)
	inst.scale = Vector3.ONE * sc
	inst.position = -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) * sc
	return holder


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ================================================================ geometria

static func cell_center(p: Vector2i) -> Vector3:
	return Vector3(p.x * S, 0, p.y * S)


func tomb_world(key: String, i: int) -> Vector3:
	var t: Dictionary = eng.tiles[key]
	var tp: Array = D.TILES[t["k"]].get("tp", [[0.82, 0.18], [0.18, 0.82]])
	var f := Vector2(tp[i % tp.size()][0], tp[i % tp.size()][1])
	for r in posmod(int(t["r"]), 4):
		f = Vector2(1.0 - f.y, f.x)
	var c := cell_center(GHEngine.cell("c:" + key))
	return c + Vector3((f.x - 0.5) * S, 0.02, (f.y - 0.5) * S)


func _build_tile(key: String) -> void:
	var t: Dictionary = eng.tiles[key]
	var root := Node3D.new()
	root.position = cell_center(GHEngine.cell("c:" + key))
	tiles_root.add_child(root)
	tile_nodes[key] = root
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(S, S)
	floor_.mesh = pm
	floor_.rotation.y = -int(t["r"]) * PI * 0.5
	floor_.material_override = _tex_mat(UI.tile_tex(t["k"]))
	root.add_child(floor_)
	# Reborn: pareti di mattoni modellate in Blender sul contorno del disegno della tessera
	var wp := "res://assets/reborn/models/tiles/%s.glb" % t["k"]
	if UI.reborn and ResourceLoader.exists(wp):
		var walls: Node3D = load(wp).instantiate()
		walls.rotation.y = -int(t["r"]) * PI * 0.5
		root.add_child(walls)
		for mi in walls.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _wall_mat()
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return
	# gallerie in rilievo: blocchi di roccia dove non ci sono corridoi
	var room: bool = t["k"] == "covo" or t["k"] == "cimitero"
	var m := D.open_mask(t["k"], int(t["r"]))
	var w := S * 0.5
	var b := (S - w) * 0.5
	if room:
		b = S * 0.1
	var blocks := []
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			blocks.append([Vector3(cx * (S - b) * 0.5, 0, cz * (S - b) * 0.5), Vector3(b, 0, b)])
	if not room:
		for d in 4:
			if m & (1 << d) != 0:
				continue
			var dv: Vector2i = D.DIRS[d]
			if dv.x == 0:
				blocks.append([Vector3(0, 0, dv.y * (S - b) * 0.5), Vector3(w, 0, b)])
			else:
				blocks.append([Vector3(dv.x * (S - b) * 0.5, 0, 0), Vector3(b, 0, w)])
	for bl in blocks:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(bl[1].x - 0.02, WALL_H, bl[1].z - 0.02)
		mi.mesh = bm
		mi.position = bl[0] + Vector3(0, WALL_H * 0.5, 0)
		mi.material_override = _mat("wall", Color("#1c2216"), 0.95)
		root.add_child(mi)
	# bordo della tessera
	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(S, 0.04, S)
	edge.mesh = em
	edge.position.y = -0.03
	edge.material_override = _mat("edge", Color("#050605"))
	root.add_child(edge)


## Estensione delle fogne (in coordinate del mondo): Rect2 sul piano x/z.
func _sewer_rect() -> Rect2:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for key in eng.tiles:
		var c := cell_center(GHEngine.cell("c:" + key))
		mn = mn.min(Vector2(c.x, c.z) - Vector2.ONE * S * 0.5)
		mx = mx.max(Vector2(c.x, c.z) + Vector2.ONE * S * 0.5)
	return Rect2(mn, mx - mn)


## Dove sta ogni luogo: sospeso in superficie sopra il suo tombino se chi guarda sa dov'è,
## altrimenti in una colonna a destra delle fogne.
var surface := {}                  # obiettivo -> chiave tessera del tombino (solo per i luoghi rivelati)
var tomb_of := {}                  # obiettivo -> posizione del tombino

func _layout_buildings() -> void:
	surface = {}
	tomb_of = {}
	var r := _sewer_rect()
	var n_surf := 0
	for key in eng.tiles:
		var t: Dictionary = eng.tiles[key]
		for i in (t["tomb"] as Array).size():
			var k: String = t["tomb"][i]
			if k == "" or surface.has(k) or not view.sees_tomb(k):
				continue
			surface[k] = key
			var tp := tomb_world(key, i)
			tomb_of[k] = tp
			n_surf += 1
	# i luoghi in superficie partono sopra il loro tombino, un po' spinti verso l'esterno, e si
	# allontanano fra loro finché non si toccano più (il pozzo resta collegato al tombino)
	var ctr := r.get_center()
	var pos := {}
	for k in surface:
		var tp: Vector3 = tomb_of[k]
		var d := Vector2(tp.x, tp.z) - ctr
		pos[k] = Vector2(tp.x, tp.z) + (d.normalized() * 0.5 if d.length() > 0.01 else Vector2.ZERO)
	var ks := surface.keys()
	ks.sort()
	for it in 60:
		for a in ks.size():
			for b in range(a + 1, ks.size()):
				var pa: Vector2 = pos[ks[a]]
				var pb: Vector2 = pos[ks[b]]
				var dd := pb - pa
				var ln := dd.length()
				if ln < MIN_GAP:
					var push := (dd / maxf(ln, 0.001) if ln > 0.001 else Vector2(1, 0)) * (MIN_GAP - ln) * 0.5
					pos[ks[a]] = pa - push
					pos[ks[b]] = pb + push
	for k in ks:
		bpos[k] = Vector3(pos[k].x, SURF_Y, pos[k].y)
	var idx := 0
	for k in D.OBJ_ORDER:
		if surface.has(k):
			continue
		var col := idx % 2
		var row := idx / 2
		bpos[k] = Vector3(r.end.x + 2.0 + col * COL_STEP, CITY_Y, r.position.y + 0.8 + row * COL_STEP)
		idx += 1
	ring_r = maxf(r.size.x, r.size.y)


# ================================================================ ricostruzione

func _rebuild() -> void:
	_dirty = false
	if eng == null or not is_inside_tree():
		return
	for key in eng.tiles:
		if not tile_nodes.has(key):
			_build_tile(key)
	_layout_buildings()
	for c in dyn.get_children():
		dyn.remove_child(c)
		c.queue_free()
	hl_mats = []
	# evidenziazioni delle tessere e caselle nuove
	for loc in allowed:
		if not loc.begins_with("c:"):
			continue
		var p := GHEngine.cell(loc)
		var key := "%d,%d" % [p.x, p.y]
		if eng.tiles.has(key):
			_plate(cell_center(p), UI.ACID, 0.28)
		else:
			_plate(cell_center(p), UI.ACID, 0.18, true)
	if source.begins_with("c:"):
		_plate(cell_center(GHEngine.cell(source)), UI.SLIME, 0.35)
	if focus.begins_with("c:"):
		_plate(cell_center(GHEngine.cell(focus)), UI.BLOOD_L, 0.35)
	if not ghost.is_empty():
		var gi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(S, S)
		gi.mesh = pm
		gi.position = cell_center(Vector2i(ghost[1], ghost[2])) + Vector3(0, 0.05, 0)
		gi.rotation.y = -int(ghost[3]) * PI * 0.5
		gi.material_override = _tex_mat(UI.tile_tex(ghost[0]), 0.85)
		dyn.add_child(gi)
	# tombini e tubi verso la città
	for key in eng.tiles:
		var t: Dictionary = eng.tiles[key]
		for i in (t["tomb"] as Array).size():
			var k: String = t["tomb"][i]
			var p3 := tomb_world(key, i)
			var on := allowed_tombs.has("c:%s|%s" % [key, k])
			var disk := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.2
			cm.bottom_radius = 0.2
			cm.height = 0.06
			disk.mesh = cm
			disk.position = p3 + Vector3(0, 0.05, 0)
			var col := Color("#5a5a50")
			var txt := "—"
			if k != "":
				if view.sees_tomb(k):
					txt = _short(k)
					col = UI.BLOOD if eng.objs[k]["dev"] else Color("#3b78b4")
				else:
					txt = "?"
					col = Color("#6b55a0")
			disk.material_override = _mat("tomb_" + col.to_html(), col, 0.4, 0.5, Color(col, 0.6))
			dyn.add_child(disk)
			if on:
				_halo(p3 + Vector3(0, 0.08, 0), 0.34, UI.ACID)
			_label(p3 + Vector3(0, 0.45, 0), txt, 34, Color.WHITE if k != "" else UI.MUTED, col.darkened(0.5))
	# pedine nelle fogne
	for key in eng.tiles:
		var loc: String = "c:" + key
		var c := cell_center(GHEngine.cell(loc))
		var gh := eng.ghouls_at(loc)
		var hu := eng.ids_at(loc, "VFR")
		if not gh.is_empty():
			_stack(gh, c + Vector3(-0.42, 0, 0.15), true)
		if not hu.is_empty():
			_stack(hu, c + Vector3(0.42, 0, 0.15), false)
		if eng.tiles[key]["k"] == "covo" or eng.tiles[key]["k"] == "cimitero":
			_label(c + Vector3(0, 0.12, S * 0.42), "COVO" if eng.tiles[key]["k"] == "covo" else "CIMITERO", 48, UI.BLOOD_L if eng.tiles[key]["k"] == "covo" else UI.BONE, Color.BLACK, true)
	# la città
	for k in D.OBJ_ORDER:
		_building(k)


## Cilindro da a a b (il pozzo che sale dal tombino al luogo in superficie).
func _beam(a: Vector3, b: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.25
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = m
	dyn.add_child(mi)
	mi.global_position = (a + b) * 0.5
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.0001:
		mi.global_basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))


func _short(k: String) -> String:
	return {"cattedrale": "CAT", "ospedale": "OSP", "polizia": "POL", "radiotv": "TV", "universita": "UNI",
		"residenziali": "RES", "porto": "POR", "popolari": "POP", "sportivo": "SPO", "commerciale": "COM"}[k]


func _plate(c: Vector3, col: Color, alpha: float, frontier := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(S * 0.96, 0.02 if not frontier else 0.3, S * 0.96)
	mi.mesh = bm
	mi.position = c + Vector3(0, WALL_H + 0.02 if not frontier else 0.15, 0)
	mi.material_override = _glow_mat(col, alpha)
	dyn.add_child(mi)
	if frontier:
		_label(c + Vector3(0, 0.5, 0), "+", 90, UI.ACID, Color.BLACK)


func _halo(p: Vector3, r: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.8
	tm.outer_radius = r
	mi.mesh = tm
	mi.position = p
	mi.material_override = _glow_mat(col, 0.9)
	dyn.add_child(mi)


func _label(p: Vector3, txt: String, size: int, col: Color, outline: Color, flat := false) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font = UI.font_bold
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_modulate = outline
	l.outline_size = 10
	l.position = p
	if flat:
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.font = UI.font_title
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = not flat
	dyn.add_child(l)
	return l


## Tubo luminoso dal tombino al piedistallo dell'obiettivo.
func _pipe(from: Vector3, k: String, col: Color) -> void:
	var to: Vector3 = bpos[k] + Vector3(0, -0.2, 0)
	var mid := (from + to) * 0.5 + Vector3(0, 1.4, 0)
	var prev := from
	var n := 10
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = prev.distance_to(p)
		cm.radial_segments = 6
		seg.mesh = cm
		dyn.add_child(seg)
		seg.global_position = (prev + p) * 0.5
		var dir := (p - prev).normalized()
		if absf(dir.dot(Vector3.UP)) < 0.999:
			seg.look_at(seg.global_position + dir, Vector3.UP)
			seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		seg.material_override = _mat("pipe_" + col.to_html(), col, 0.4, 0.3, Color(col, 0.25 if col == UI.BLOOD else 1.2))
		prev = p


func _standee(id: int, at: Vector3, face: bool, h := 0.8) -> void:
	var c: Dictionary = eng.cs[id]
	var ghoul: bool = c["t"] == "G" or c["t"] == "S"
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.19
	cm.height = 0.06
	base.mesh = cm
	base.position = at + Vector3(0, 0.03, 0)
	var bc := UI.GHOUL_C if ghoul else UI.seat_col(eng, maxi(1, int(c["o"])))
	base.material_override = _mat("base_" + bc.to_html(), bc, 0.5, 0.2)
	dyn.add_child(base)
	var mname := "volontario"
	if ghoul:
		mname = "ghoul_%d" % int(c["v"]) if c["t"] == "G" and models.has("ghoul_%d" % int(c["v"])) else "ghoul"
	var mdl := _model(mname, h) if (ghoul and face) or (not ghoul and c["t"] == "V") else null
	if mdl != null:
		mdl.position = at + Vector3(0, 0.06, 0)
		dyn.add_child(mdl)
		return
	var sp := Sprite3D.new()
	sp.texture = UI.counter_tex(c) if face else UI.ghoul_back()
	sp.pixel_size = h / float(sp.texture.get_height())
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.double_sided = true
	sp.shaded = false
	sp.position = at + Vector3(0, 0.06 + h * 0.5, 0)
	dyn.add_child(sp)


func _stack(ids: Array, at: Vector3, ghoul: bool) -> void:
	var show := mini(ids.size(), 4)
	var offs := [Vector3(0, 0, 0), Vector3(0.22, 0, -0.18), Vector3(-0.22, 0, -0.18), Vector3(0, 0, -0.34)]
	for i in show:
		var id: int = ids[i]
		var face: bool = view.sees_ghoul(id) if ghoul else true
		_standee(id, at + offs[i], face)
	if ids.size() > 1:
		_label(at + Vector3(0, 1.15, 0), str(ids.size()), 44, Color.WHITE, UI.GHOUL_C.darkened(0.4) if ghoul else UI.BLOOD)


func _building(k: String) -> void:
	var p: Vector3 = bpos[k]
	var o: Dictionary = eng.objs[k]
	var dev: bool = o["dev"]
	var ow: int = o["owner"]
	var l := "o:" + k
	var floating := surface.has(k)
	var pad := MeshInstance3D.new()
	if floating:
		# una lastra di strada in superficie, collegata al tombino da un pozzo
		var bm := BoxMesh.new()
		bm.size = Vector3(1.75, 0.12, 1.75)
		pad.mesh = bm
		pad.position = p - Vector3(0, 0.06, 0)
		var tp: Vector3 = tomb_of[k]
		var sc := UI.BLOOD if dev else Color("#3b78b4")
		_beam(tp + Vector3(0, WALL_H, 0), p - Vector3(0, 0.12, 0), 0.12, _mat("shaft_" + sc.to_html(), sc.darkened(0.35), 0.5, 0.3, Color(sc, 0.5)))
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.95
		cm.bottom_radius = 1.05
		cm.height = CITY_Y
		pad.mesh = cm
		pad.position = Vector3(p.x, CITY_Y * 0.5, p.z)
	pad.material_override = _mat("pad_dev" if dev else "pad", Color("#2a1512") if dev else Color("#2b2f26"), 0.85)
	dyn.add_child(pad)
	if ow >= 1:
		_halo(p + Vector3(0, 0.02, 0), 1.0, UI.seat_col(eng, ow))
	var hl := ""
	if view.obj_cards.has(k):
		hl = view.obj_cards[k].hl
	if hl != "":
		_halo(p + Vector3(0, 0.08, 0), 1.15, UI.SLIME if hl == "src" or hl == "sel" else UI.ACID)
	if focus == l:
		_halo(p + Vector3(0, 0.12, 0), 1.25, UI.BLOOD_L)
	# l'edificio: modello 3D (Reborn) oppure la tessera Obiettivo in piedi
	var wdt := 1.55 if floating else 1.9
	var mdl := _model(k + "_dev", 0.0, wdt) if dev and models.has(k + "_dev") else _model(k, 0.0, wdt)
	if mdl != null:
		mdl.position = p
		mdl.rotation.y = MODEL_YAW          # il fronte del diorama guarda verso la telecamera iniziale
		dyn.add_child(mdl)
	else:
		var sp := Sprite3D.new()
		sp.texture = UI.obj_tex(k, dev)
		sp.pixel_size = 2.1 / float(sp.texture.get_width())
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.shaded = false
		sp.position = p + Vector3(0, 0.75 + (0.2 if k == "cattedrale" else 0.0), -0.35)
		if k == "cattedrale":
			sp.pixel_size *= 1.25
		dyn.add_child(sp)
	var ly := 1.75 + (0.35 if k == "cattedrale" else 0.0)
	if mdl != null:
		ly = _aabb(mdl.get_child(0)).size.y * mdl.get_child(0).scale.y + 0.45
	_label(p + Vector3(0, ly, 0 if mdl != null else -0.35), "%s ×%d" % [D.obj_name(k), D.OBJECTIVES[k]["mult"]], 30, UI.ACID_L if not dev else UI.BLOOD_L, Color.BLACK)
	if dev:
		var fire := OmniLight3D.new()
		fire.position = p + Vector3(0, 1.0, 0)
		fire.light_color = Color("#ff4422")
		fire.light_energy = 0.45 if mdl != null else 1.4
		fire.omni_range = 2.8
		dyn.add_child(fire)
	# chi c'è
	var hu := eng.ids_at(l, "VFPMR")
	if not hu.is_empty():
		if view.sees_obj():
			var show := mini(hu.size(), 6)
			for i in show:
				var a := PI * (0.25 + 0.5 * i / maxf(1.0, show - 1.0))
				_standee(hu[i], p + Vector3(cos(a) * 0.7, 0.0, sin(a) * 0.45 + 0.2), true, 0.55)
			if hu.size() > show:
				_label(p + Vector3(0, 0.7, 0.9), "+%d" % (hu.size() - show), 36, Color.WHITE, UI.BLOOD)
		else:
			var sp2 := Sprite3D.new()
			sp2.texture = UI.human_back()
			sp2.pixel_size = 0.45 / float(sp2.texture.get_height())
			sp2.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			sp2.shaded = false
			sp2.position = p + Vector3(0, 0.3, 0.75)
			dyn.add_child(sp2)
			_label(p + Vector3(0, 0.75, 0.75), "%d" % hu.size(), 40, Color.WHITE, UI.BLOOD)
	var gh := eng.ghouls_at(l)
	if not gh.is_empty():
		_stack(gh, p + Vector3(-0.75, 0, 0.45), true)


# ================================================================ telecamera e input

func _process(delta: float) -> void:
	pulse += delta
	var a := 0.7 + 0.3 * sin(pulse * 4.0)
	for m in hl_mats:
		m.albedo_color.a = float(m.get_meta("a", 0.5)) * a


func _update_cam() -> void:
	pivot.position = target
	pivot.rotation_degrees = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, dist)
	cam.rotation = Vector3.ZERO


var _fit_rect := Rect2()
var _fit_sig := ""
var user_moved := false

func fit() -> void:
	if eng == null:
		return
	_layout_buildings()
	var r := _sewer_rect()
	var pts: Array = []
	for key in eng.tiles:
		var c := cell_center(GHEngine.cell("c:" + key))
		for dx in [-1, 1]:
			for dz in [-1, 1]:
				pts.append(c + Vector3(dx * S * 0.5, 0, dz * S * 0.5))
	for k in bpos:
		var bp: Vector3 = bpos[k]
		for dx in [-1, 1]:
			for dz in [-1, 1]:
				pts.append(bp + Vector3(dx * 0.95, 0, dz * 0.95))
		pts.append(bp + Vector3(0, 1.9, 0))
	for k in bpos:
		r = r.expand(Vector2(bpos[k].x, bpos[k].z) + Vector2(1.2, 1.2))
		r = r.expand(Vector2(bpos[k].x, bpos[k].z) - Vector2(1.2, 1.2))
	_fit_rect = r
	var c0 := r.get_center()
	target = Vector3(c0.x, 1.0, c0.y)
	yaw = 0.0
	pitch = -55.0
	dist = 20.0
	# area utile dello schermo: sotto c'è la barra delle decisioni
	var area := Rect2(Vector2(0.05, 0.05), Vector2(0.90, 0.72))
	if size.x > 10 and Vector2(vp.size) != size:
		vp.size = Vector2i(size)
	for it in 8:
		_update_cam()
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		var vs := Vector2(vp.size)
		for p3 in pts:
			var sp := cam.unproject_position(p3) / vs
			mn = mn.min(sp)
			mx = mx.max(sp)
		var box := Rect2(mn, mx - mn)
		var k := maxf(box.size.x / area.size.x, box.size.y / area.size.y)
		# sposta il centro inquadrato verso il centro dell'area utile, poi regola la distanza
		var off := box.get_center() - area.get_center()
		var right := cam.global_transform.basis.x
		var fwd := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
		target += right * off.x * dist * 0.75 - fwd * off.y * dist * 0.95
		dist = clampf(dist * lerpf(1.0, k, 0.85), 4.0, 80.0)
	_fitted = true
	_update_cam()


func ensure_visible() -> void:
	if eng == null:
		return
	# l'inquadratura si fa solo la prima volta (e con il pulsante Centra): poi resta dove la mette il giocatore
	if not _fitted:
		fit()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			dist = clampf(dist * (0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.11), 4.0, 80.0)
			user_moved = true
			_update_cam()
			accept_event()
			return
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			drag_btn = mb.button_index
			drag_from = mb.position
			drag_moved = false
		elif not mb.pressed and mb.button_index == drag_btn:
			if not drag_moved and drag_btn == MOUSE_BUTTON_LEFT:
				_click(mb.position)
			drag_btn = -1
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_btn >= 0:
			if mm.position.distance_to(drag_from) > 6.0:
				drag_moved = true
			if drag_moved:
				user_moved = true
				if drag_btn == MOUSE_BUTTON_LEFT:
					yaw -= mm.relative.x * 0.25
					pitch = clampf(pitch - mm.relative.y * 0.2, -89.0, -15.0)
				else:
					var right := cam.global_transform.basis.x
					var fwd := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
					var k := dist * 0.0016
					target += (-right * mm.relative.x + fwd * mm.relative.y) * k
				_update_cam()
		else:
			tooltip_text = _tooltip_at(mm.position)
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / (ev as InputEventMagnifyGesture).factor, 4.0, 80.0)
		_update_cam()
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		yaw -= pg.delta.x * 2.0
		pitch = clampf(pitch - pg.delta.y * 2.0, -89.0, -15.0)
		_update_cam()


func _screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p) * (size / Vector2(vp.size))


func _pick(pos: Vector2) -> Dictionary:
	if eng == null:
		return {}
	# tombini
	for key in eng.tiles:
		var t: Dictionary = eng.tiles[key]
		for i in (t["tomb"] as Array).size():
			var p3 := tomb_world(key, i)
			if cam.is_position_behind(p3):
				continue
			if _screen(p3).distance_to(pos) < 18.0 and t["tomb"][i] != "":
				return {"tomb": t["tomb"][i], "tile": "c:" + key}
	# edifici
	var best := ""
	var bd := 1e9
	for k in bpos:
		var c: Vector3 = bpos[k] + Vector3(0, 0.45, 0)
		if cam.is_position_behind(c):
			continue
		var sp := _screen(c)
		var rad := (_screen(c + cam.global_transform.basis.x * 0.8) - sp).length()
		var dd := sp.distance_to(pos)
		if dd < rad and dd < bd:
			bd = dd
			best = k
	if best != "":
		return {"obj": best}
	# tessere: raggio sul piano delle fogne
	var vpp := pos * (Vector2(vp.size) / size)
	var o := cam.project_ray_origin(vpp)
	var d := cam.project_ray_normal(vpp)
	if absf(d.y) < 0.0001:
		return {}
	var tt := (WALL_H * 0.5 - o.y) / d.y
	if tt < 0:
		return {}
	var hit := o + d * tt
	var cx := floori(hit.x / S + 0.5)
	var cz := floori(hit.z / S + 0.5)
	return {"cell": "c:%d,%d" % [cx, cz]}


func _click(pos: Vector2) -> void:
	var r := _pick(pos)
	if r.has("tomb"):
		tomb_clicked.emit(r["tile"], r["tomb"])
	elif r.has("obj"):
		view._on_loc_click("o:" + r["obj"])
	elif r.has("cell"):
		loc_clicked.emit(r["cell"])


func _tooltip_at(pos: Vector2) -> String:
	var r := _pick(pos)
	if r.has("obj"):
		return view.obj_tooltip(r["obj"])
	if r.has("tomb"):
		return view.tile_tooltip(r["tile"])
	if r.has("cell"):
		return view.tile_tooltip(r["cell"])
	return ""
