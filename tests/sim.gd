extends SceneTree
## Partite simulate fra IA, senza grafica: controlla che le regole reggano e misura esiti e durata.
## Uso: godot --headless --path . -s tests/sim.gd -- [partite] [umani 2/3] [livello Ghoul] [livello Umani]
## GH_LOG=1 stampa il diario della prima partita.

var errors := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var nh := int(args[1]) if args.size() > 1 else 2
	var lg := int(args[2]) if args.size() > 2 else 1
	var lh := int(args[3]) if args.size() > 3 else 1
	_run(games, nh, lg, lh)


func _run(games: int, nh: int, lg: int, lh: int) -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	var wins := {"ghoul": 0, "umani": 0}
	var reasons := {}
	var turns := 0
	var devs := 0
	for g in games:
		var eng := GHEngine.new()
		eng.headless = true
		root.add_child(eng)
		var seats := [{"name": "Ghoul", "ai": true, "level": lg}]
		for i in nh:
			seats.append({"name": "", "ai": true, "level": lh})
		eng.setup({"seats": seats, "seed": 1000 + g, "max_turns": int(OS.get_environment("GH_MAXT")) if OS.get_environment("GH_MAXT") != "" else 40})
		for i in nh + 1:
			eng.ais[i] = GHAI.new(lg if i == 0 else lh, 50 + g * 7 + i)
		eng.changed.connect(_check.bind(eng))
		await eng.run()
		if OS.get_environment("GH_LOG") == "1" and g == 0:
			for l in eng.log_lines:
				print("  ", l)
		wins[eng.winner] = wins.get(eng.winner, 0) + 1
		reasons[eng.end_reason.substr(0, 40)] = reasons.get(eng.end_reason.substr(0, 40), 0) + 1
		turns += eng.turn_no
		for k in eng.objs:
			if eng.objs[k]["dev"]:
				devs += 1
		var line := []
		for r in eng.results:
			line.append("%s %d" % [eng.pname(r["seat"]), r["total"]])
		print("partita %d: %s al turno %d — %s | %s" % [g + 1, eng.winner, eng.turn_no, eng.end_reason, ", ".join(line)])
		if OS.get_environment("GH_DIAG") == "1":
			var stacks := {}
			for id in eng.board_ghouls():
				stacks[eng.cs[id]["loc"]] = stacks.get(eng.cs[id]["loc"], 0) + 1
			print("   catt tiles=", eng.tiles_for("cattedrale"), " nota=", eng.ghoul_known.has("cattedrale"), " pezzi catt=", eng.ids_at("o:cattedrale").size(),
				" difesa=", eng.humans_at("o:cattedrale").size(), " mazzo=", eng.tile_deck.size(), " locaz=", eng.loc_tokens, " ghoul=", stacks, " pool g=", eng.gpool.size(), " h=", eng.hpool.size())
		eng.queue_free()
	print("vittorie: ", wins, "  turni medi %.1f  obiettivi devastati medi %.1f" % [float(turns) / games, float(devs) / games])
	print("finali: ", reasons)
	print("errori: %d   tempo %.1f s" % [errors, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if errors > 0 else 0)


func _check(eng: GHEngine) -> void:
	# ogni pedina sta in un solo posto: contenitori e tabellone coerenti
	var seen := {}
	for id in eng.gpool + eng.hpool:
		if seen.has(id):
			_err(eng, "pedina %d due volte nei contenitori" % id)
		seen[id] = true
		if eng.cs[id]["loc"] != "":
			_err(eng, "pedina %d nel contenitore ma in %s" % [id, eng.cs[id]["loc"]])
	for id in eng.cs:
		var c: Dictionary = eng.cs[id]
		if c["loc"] == "" and not seen.has(id):
			_err(eng, "pedina %d (%s) persa" % [id, c["t"]])
		if (c["t"] == "V" or c["t"] == "F") and c["loc"] != "" and c["loc"] != "out" and int(c["o"]) < 1:
			_err(eng, "pedina umana %d senza padrone" % id)


func _err(eng: GHEngine, t: String) -> void:
	errors += 1
	if errors < 10:
		print("ERRORE turno %d: %s" % [eng.turn_no, t])
