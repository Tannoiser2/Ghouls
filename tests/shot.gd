extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## xvfb-run godot --path . -s res://tests/shot.gd -- <modo> [turni]
## modo: menu | rules | umano (Rosso persona) | ghoul (Ghoul persona) | ia (tutti IA)
## Nelle partite le decisioni della persona le prende l'IA, con uno screenshot alla prima
## richiesta di ogni tipo.

var main
var n := 0
var seen := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "umano"
	var turns := int(args[1]) if args.size() > 1 else 6
	await wait(8)
	if mode == "menu":
		await shot("menu")
		main.current._online_panel()
		await wait(4)
		await shot("online")
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("regole")
		for i in 3:
			main.current.get_child(1).get_child(0).get_child(0).get_child(1).get_child(i + 1).pressed.emit()
			await wait(3)
			await shot("regole_%d" % (i + 2))
		quit()
		return
	var seats := [{"name": "Ghoul", "ai": not (mode in ["ghoul", "tutti"]), "level": 1}, {"name": "Rosso", "ai": not (mode in ["umano", "tutti"]), "level": 1},
		{"name": "Verde", "ai": mode != "tutti", "level": 1}, {"name": "Giallo", "ai": mode != "tutti", "level": 1}]
	main.start_game({"seats": seats, "ai_delay": 0.0, "max_turns": 30, "view3d": OS.get_environment("GH_3D") == "1", "style": "reborn" if OS.get_environment("GH_RB") == "1" else "classico", "seed": int(OS.get_environment("GH_SEED")) if OS.get_environment("GH_SEED") != "" else 7})
	await wait(10)
	var view = main.current
	var ai := GHAI.new(1, 3)
	var t0 := Time.get_ticks_msec()
	var combat_shots := 0
	while Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		var e: GHEngine = view.engine
		if e.game_over:
			await wait(20)
			await shot("fine")
			break
		if OS.get_environment("GH_PICK") == "1" and e.turn_no >= 3 and view.map == view.map3d:
			var b: Board3D = view.map3d
			var ok := 0
			var bad := []
			for key in e.tiles:
				var loc: String = "c:" + key
				var r := b._pick(b._screen(Board3D.cell_center(GHEngine.cell(loc)) + Vector3(0.3, 0.13, 0.3)))
				if r.get("cell", "") == loc:
					ok += 1
				else:
					bad.append([loc, r])
			for k in b.bpos:
				var r2 := b._pick(b._screen(b.bpos[k] + Vector3(0, 0.8, -0.35)))
				if r2.get("obj", "") == k:
					ok += 1
				else:
					bad.append([k, r2])
			print("PICK ok=", ok, " sbagliati=", bad)
			quit()
			return
		if e.turn_no > turns:
			await shot("dopo_%d_turni" % turns)
			break
		if is_instance_valid(view.curtain):
			if not seen.has("tendina"):
				seen["tendina"] = true
				await shot("tendina")
			view.curtain.queue_free()
			await wait(2)
		var req: Dictionary = view.pending
		if req.is_empty():
			if not e.combat.is_empty() and combat_shots < 2 and mode == "ia":
				combat_shots += 1
				await shot("combattimento_ia")
			continue
		var k: String = req["type"] + "_" + str(req.get("ctx", ""))
		if not seen.has(k):
			seen[k] = true
			await wait(6)
			await shot(k)
		var r = ai.decide(e, req["seat"], req)
		# per vedere la selezione dei movimenti: prima si sceglie la partenza, poi si fotografa
		if (req["type"] == "gmove" or req["type"] == "hmove") and r is Dictionary and not r.is_empty() and not seen.has(k + "_sel"):
			seen[k + "_sel"] = true
			view._on_loc_click(e.cs[r["ids"][0]]["loc"])
			await wait(6)
			await shot(k + "_selezione")
		view._provide(r)
	quit()
