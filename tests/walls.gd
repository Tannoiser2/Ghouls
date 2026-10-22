extends SceneTree
## Prova delle pareti Reborn: un pezzo di fogne finto inquadrato da vicino.
## xvfb-run godot --path . -s res://tests/walls.gd -- [yaw] [pitch] [dist]

class FakeView:
	extends RefCounted
	var obj_cards := {}
	func sees_tomb(_k): return true
	func sees_ghoul(_id): return true
	func sees_obj(): return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	UI.reborn = true
	var e := GHEngine.new()
	e.headless = true
	root.add_child(e)
	e.setup({"seats": [{"name": "G", "ai": true}, {"name": "", "ai": true}, {"name": "", "ai": true}], "seed": 3})
	e.tiles = {"0,0": {"k": "covo", "r": 0, "tomb": []}, "1,0": {"k": "croce", "r": 0, "tomb": []},
		"2,0": {"k": "curva_t", "r": 1, "tomb": ["ospedale"]}, "1,1": {"k": "dritto", "r": 0, "tomb": []},
		"1,-1": {"k": "tt", "r": 2, "tomb": ["porto"]}, "0,1": {"k": "curva", "r": 3, "tomb": []},
		"-1,0": {"k": "croce_tt", "r": 0, "tomb": ["cattedrale", "polizia"]}, "1,2": {"k": "cieco", "r": 2, "tomb": []}}
	var b := Board3D.new()
	b.view = FakeView.new()
	b.size = Vector2(1920, 1080)
	root.add_child(b)
	await process_frame
	b.set_engine(e)
	for i in 6:
		await process_frame
	b.target = Vector3(1.5, 0, 0.8)
	b.yaw = float(args[0]) if args.size() > 0 else 25.0
	b.pitch = float(args[1]) if args.size() > 1 else -38.0
	b.dist = float(args[2]) if args.size() > 2 else 6.5
	b._update_cam()
	for i in 8:
		await process_frame
	var img := b.vp.get_texture().get_image()
	img.save_png("/tmp/claude-0/pareti.png")
	print("ok")
	quit()
